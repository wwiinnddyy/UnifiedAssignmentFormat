import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..", "..", "..");
const examplesDir = join(repoRoot, "examples");
const requireFromHtmlPackage = createRequire(join(__dirname, "..", "packages", "html", "package.json"));
const { PDFDocument } = requireFromHtmlPackage("pdf-lib");

async function main() {
  const { parsePayload } = await import("../packages/core/dist/index.js");
  const { validateUafHtml } = await import("../packages/html/dist/index.js");
  const { validateUafPdf } = await import("../packages/pdf/dist/index.js");

  const csv = await readFile(join(examplesDir, "uaf_payload.sample.csv"), "utf-8");
  const html = await readFile(join(examplesDir, "sample-homework.html"), "utf-8");
  const pdf = new Uint8Array(await readFile(join(examplesDir, "sample-homework.pdf")));

  const csvPayload = parsePayload(csv);
  const htmlResult = validateUafHtml(html);
  const pdfResult = await validateUafPdf(pdf);

  assertPrintableHtml(html);
  await assertPdfQuality(pdf);

  if (!htmlResult.valid || !htmlResult.payload) {
    throw new Error(`Invalid sample HTML: ${htmlResult.errors.join("; ")}`);
  }
  if (!pdfResult.valid || !pdfResult.payload) {
    throw new Error(`Invalid sample PDF: ${pdfResult.errors.join("; ")}`);
  }

  assertSamePayload("HTML", csvPayload, htmlResult.payload);
  assertSamePayload("PDF", csvPayload, pdfResult.payload);

  console.log("Verified examples/uaf_payload.sample.csv, sample-homework.html, and sample-homework.pdf");
}

function assertSamePayload(name, expected, actual) {
  const expectedJson = JSON.stringify(expected);
  const actualJson = JSON.stringify(actual);
  if (expectedJson !== actualJson) {
    throw new Error(`${name} sample payload does not match CSV payload`);
  }
}

async function assertPdfQuality(pdf) {
  assertPdfHeader(pdf);

  const document = await PDFDocument.load(pdf);
  const pages = document.getPages();
  if (pages.length !== 1) {
    throw new Error(`Sample PDF must be exactly 1 page, received ${pages.length}`);
  }

  const { width, height } = pages[0].getSize();
  const expectedA4Portrait = { width: 595.28, height: 841.89 };
  const tolerance = 6;

  if (width >= height) {
    throw new Error(`Sample PDF must be portrait, received ${formatSize(width, height)}`);
  }

  if (
    !isCloseTo(width, expectedA4Portrait.width, tolerance) ||
    !isCloseTo(height, expectedA4Portrait.height, tolerance)
  ) {
    throw new Error(`Sample PDF page size must be close to A4 portrait, received ${formatSize(width, height)}`);
  }
}

function assertPdfHeader(pdf) {
  const expected = "%PDF";
  const actual = String.fromCharCode(...pdf.slice(0, expected.length));
  if (actual !== expected) {
    throw new Error(`Sample PDF bytes must start with ${expected}`);
  }
}

function isCloseTo(actual, expected, tolerance) {
  return Math.abs(actual - expected) <= tolerance;
}

function formatSize(width, height) {
  return `${width.toFixed(2)} x ${height.toFixed(2)} pt`;
}

function assertPrintableHtml(html) {
  const requiredFragments = [
    "<!DOCTYPE html>",
    "@page",
    "size: A4 portrait",
    "print-color-adjust: exact",
    "border-radius: 16pt",
    'id="uaf-payload-csv"',
    'data-filename="uaf_payload.csv"',
  ];

  for (const fragment of requiredFragments) {
    if (!html.includes(fragment)) {
      throw new Error(`Sample HTML is missing required fragment: ${fragment}`);
    }
  }

  if (/<link\b|<script\b|src=/i.test(html)) {
    throw new Error("Sample HTML must stay self-contained without external assets or scripts");
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
