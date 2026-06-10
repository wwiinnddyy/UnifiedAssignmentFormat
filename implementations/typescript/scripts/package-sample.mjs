import { createHash } from "node:crypto";
import { copyFile, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..", "..", "..");
const examplesDir = join(repoRoot, "examples");
const packageDir = join(examplesDir, "sample-homework.uaf");

const sources = [
  {
    role: "payload.csv",
    source: join(examplesDir, "uaf_payload.sample.csv"),
    target: "uaf_payload.csv",
    mediaType: "text/csv; charset=utf-8",
  },
  {
    role: "display.html",
    source: join(examplesDir, "sample-homework.html"),
    target: "display.html",
    mediaType: "text/html; charset=utf-8",
  },
  {
    role: "exchange.pdf",
    source: join(examplesDir, "sample-homework.pdf"),
    target: "document.pdf",
    mediaType: "application/pdf",
  },
];

async function main() {
  await rm(packageDir, { recursive: true, force: true });
  await mkdir(packageDir, { recursive: true });

  const artifacts = [];
  for (const item of sources) {
    const targetPath = join(packageDir, item.target);
    await copyFile(item.source, targetPath);
    const bytes = await readFile(targetPath);
    artifacts.push({
      role: item.role,
      path: item.target,
      mediaType: item.mediaType,
      bytes: bytes.byteLength,
      sha256: sha256(bytes),
    });
  }

  const manifest = {
    $schema: relative(packageDir, join(repoRoot, "spec", "uaf-artifact-manifest.schema.json"))
      .replace(/\\/g, "/"),
    schemaVersion: "1.0",
    packageKind: "uaf-artifact-set",
    uafVersion: "1.0",
    createdAt: new Date().toISOString(),
    entrypoints: {
      payload: "uaf_payload.csv",
      display: "display.html",
      exchange: "document.pdf",
    },
    artifacts,
    pipeline: {
      renderer: "html-to-pdf",
      printEngine: "browser-print",
      payloadAttachment: "uaf_payload.csv",
    },
  };

  await writeFile(
    join(packageDir, "uaf-manifest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
    "utf-8",
  );

  console.log(`Packaged ${packageDir}`);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
