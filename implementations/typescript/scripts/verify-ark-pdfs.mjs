import { readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const { PDFDocument } = await import("./ark-pdf-gen/node_modules/pdf-lib/dist/pdf-lib.esm.min.js");

const stylesDir = join(__dirname, "..", "..", "..", "examples", "ark-ui-styles");
const styles = ["corporate-minimal", "popucom-moderate", "ark-complex", "endfield-moderate", "exa-moderate"];

let allPassed = true;
for (const s of styles) {
  const path = join(stylesDir, `${s}.pdf`);
  try {
    const bytes = await readFile(path);
    const doc = await PDFDocument.load(bytes);
    const pages = doc.getPageCount();

    // Check for embedded files
    const pdfText = new TextDecoder("latin1").decode(bytes);
    const hasEmbeddedFile = pdfText.includes("uaf_payload.csv");

    const ok = pages >= 1 && hasEmbeddedFile;
    console.log(`${ok ? "✓" : "✗"} ${s}.pdf: ${pages} page(s), ${(bytes.length / 1024).toFixed(1)} KB, CSV embedded: ${hasEmbeddedFile}`);
    if (!ok) allPassed = false;
  } catch (e) {
    console.log(`✗ ${s}.pdf: ERROR - ${e.message}`);
    allPassed = false;
  }
}

console.log(allPassed ? "\nAll PDFs passed compliance check." : "\nSome PDFs failed compliance check.");
process.exit(allPassed ? 0 : 1);
