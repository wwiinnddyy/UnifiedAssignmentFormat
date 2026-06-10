import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, isAbsolute, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..", "..", "..");
const defaultPackageDir = resolve(repoRoot, "examples", "sample-homework.uaf");
const packageDir = resolve(process.argv[2] ?? defaultPackageDir);

async function main() {
  const { parsePayload } = await import("../packages/core/dist/index.js");
  const { validateUafHtml } = await import("../packages/html/dist/index.js");
  const { validateUafPdf } = await import("../packages/pdf/dist/index.js");

  const manifest = await readManifest(packageDir);
  validateManifestShape(manifest);

  const artifactBytes = new Map();
  for (const artifact of manifest.artifacts) {
    const bytes = await readPackageFile(packageDir, artifact.path);
    assertArtifactIntegrity(artifact, bytes);
    artifactBytes.set(artifact.path, bytes);
  }

  const csvText = new TextDecoder().decode(requiredBytes(artifactBytes, manifest.entrypoints.payload));
  const htmlText = new TextDecoder().decode(requiredBytes(artifactBytes, manifest.entrypoints.display));
  const pdfBytes = requiredBytes(artifactBytes, manifest.entrypoints.exchange);

  const payloadFromCsv = parsePayload(csvText);
  const htmlResult = validateUafHtml(htmlText);
  const pdfResult = await validateUafPdf(pdfBytes);

  if (!htmlResult.valid || !htmlResult.payload) {
    throw new Error(`Invalid packaged HTML: ${htmlResult.errors.join("; ")}`);
  }
  if (!pdfResult.valid || !pdfResult.payload) {
    throw new Error(`Invalid packaged PDF: ${pdfResult.errors.join("; ")}`);
  }

  assertSamePayload("HTML", payloadFromCsv, htmlResult.payload);
  assertSamePayload("PDF", payloadFromCsv, pdfResult.payload);

  console.log(
    JSON.stringify(
      {
        package: packageDir,
        uafVersion: manifest.uafVersion,
        artifacts: manifest.artifacts.map((artifact) => ({
          role: artifact.role,
          path: artifact.path,
          bytes: artifact.bytes,
        })),
        payload: payloadFromCsv,
      },
      null,
      2,
    ),
  );
}

async function readManifest(root) {
  const manifestBytes = await readFile(resolve(root, "uaf-manifest.json"));
  return JSON.parse(new TextDecoder().decode(manifestBytes));
}

function validateManifestShape(manifest) {
  if (manifest.schemaVersion !== "1.0") {
    throw new Error(`Unsupported manifest schemaVersion: ${manifest.schemaVersion}`);
  }
  if (manifest.packageKind !== "uaf-artifact-set") {
    throw new Error(`Unsupported packageKind: ${manifest.packageKind}`);
  }
  if (manifest.uafVersion !== "1.0") {
    throw new Error(`Unsupported uafVersion: ${manifest.uafVersion}`);
  }
  if (!manifest.entrypoints || typeof manifest.entrypoints !== "object") {
    throw new Error("Manifest must declare entrypoints");
  }
  if (!Array.isArray(manifest.artifacts)) {
    throw new Error("Manifest must declare artifacts");
  }

  for (const entrypoint of ["payload", "display", "exchange"]) {
    if (typeof manifest.entrypoints[entrypoint] !== "string") {
      throw new Error(`Manifest entrypoints.${entrypoint} must be a string`);
    }
  }
}

async function readPackageFile(root, relativePath) {
  const filePath = resolvePackagePath(root, relativePath);
  return new Uint8Array(await readFile(filePath));
}

function resolvePackagePath(root, relativePath) {
  if (
    typeof relativePath !== "string" ||
    relativePath.length === 0 ||
    isAbsolute(relativePath) ||
    /^[A-Za-z]:/.test(relativePath) ||
    relativePath.includes("://")
  ) {
    throw new Error(`Invalid package path: ${relativePath}`);
  }

  const resolvedRoot = resolve(root);
  const resolvedPath = resolve(resolvedRoot, relativePath);
  const rootWithSeparator = resolvedRoot.endsWith(sep)
    ? resolvedRoot
    : `${resolvedRoot}${sep}`;

  if (
    resolvedPath !== resolvedRoot &&
    !resolvedPath.toLowerCase().startsWith(rootWithSeparator.toLowerCase())
  ) {
    throw new Error(`Package path escapes the package root: ${relativePath}`);
  }

  return resolvedPath;
}

function assertArtifactIntegrity(artifact, bytes) {
  if (artifact.bytes !== bytes.byteLength) {
    throw new Error(
      `Artifact ${artifact.path} byte size mismatch: expected ${artifact.bytes}, got ${bytes.byteLength}`,
    );
  }

  const actualHash = createHash("sha256").update(bytes).digest("hex");
  if (artifact.sha256 !== actualHash) {
    throw new Error(`Artifact ${artifact.path} sha256 mismatch`);
  }
}

function requiredBytes(artifactBytes, path) {
  const bytes = artifactBytes.get(path);
  if (!bytes) {
    throw new Error(`Manifest entrypoint is not listed as an artifact: ${path}`);
  }
  return bytes;
}

function assertSamePayload(name, expected, actual) {
  if (JSON.stringify(expected) !== JSON.stringify(actual)) {
    throw new Error(`${name} payload does not match CSV payload`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
