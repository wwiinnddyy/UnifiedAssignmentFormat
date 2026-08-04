/**
 * Generate UAF-compliant PDFs from Ark UI-styled HTML files.
 *
 * For each HTML file in examples/ark-ui-styles/:
 *   1. Convert HTML → PDF via Chrome/Edge headless --print-to-pdf
 *   2. Extract the CSV payload from the <template id="uaf-payload-csv"> tag
 *   3. Embed the CSV as an attached file in the PDF using pdf-lib
 *   4. Write the final PDF to examples/ark-ui-styles/{style}.pdf
 *
 * Usage:  node scripts/generate-ark-pdfs.mjs
 * Deps:   pdf-lib (npm install pdf-lib)
 */

import { access, readFile, writeFile, mkdtemp, rm } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { tmpdir } from "node:os";
import { spawn } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..", "..", "..");
const stylesDir = join(repoRoot, "examples", "ark-ui-styles");

const STYLES = [
  "corporate-minimal",
  "popucom-moderate",
  "ark-complex",
  "endfield-moderate",
  "exa-moderate",
];

// ── Browser discovery (mirrors htmlToPdf.ts findBrowserExecutable) ──

async function findBrowser() {
  const candidates = [
    process.env.UAF_CHROMIUM_EXECUTABLE,
    process.env.PUPPETEER_EXECUTABLE_PATH,
    process.env.CHROME_PATH,
    process.platform === "win32"
      ? `${process.env.PROGRAMFILES ?? ""}\\Google\\Chrome\\Application\\chrome.exe`
      : undefined,
    process.platform === "win32"
      ? `${process.env["PROGRAMFILES(X86)"] ?? ""}\\Google\\Chrome\\Application\\chrome.exe`
      : undefined,
    process.platform === "win32"
      ? `${process.env.LOCALAPPDATA ?? ""}\\Google\\Chrome\\Application\\chrome.exe`
      : undefined,
    process.platform === "win32"
      ? `${process.env.PROGRAMFILES ?? ""}\\Microsoft\\Edge\\Application\\msedge.exe`
      : undefined,
    process.platform === "win32"
      ? `${process.env["PROGRAMFILES(X86)"] ?? ""}\\Microsoft\\Edge\\Application\\msedge.exe`
      : undefined,
    process.platform === "darwin"
      ? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
      : undefined,
    process.platform === "darwin"
      ? "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
      : undefined,
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/usr/bin/microsoft-edge",
  ].filter(Boolean);

  for (const c of candidates) {
    try {
      await access(c);
      return c;
    } catch {
      // try next
    }
  }
  return null;
}

// ── Chrome headless HTML→PDF ──

async function htmlToPdfFile(browserPath, htmlPath, pdfPath) {
  const args = [
    "--headless=new",
    "--disable-gpu",
    "--no-sandbox",
    "--disable-dev-shm-usage",
    `--print-to-pdf=${pdfPath}`,
    "--print-to-pdf-no-header",
    pathToFileURL(htmlPath).href,
  ];

  await new Promise((resolve, reject) => {
    const child = spawn(browserPath, args, {
      windowsHide: true,
      stdio: ["ignore", "ignore", "pipe"],
    });
    let stderr = "";
    child.stderr.setEncoding("utf-8");
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => {
      if (code !== 0) reject(new Error(`Browser print failed (code ${code}): ${stderr.trim()}`));
      else resolve();
    });
    child.on("error", reject);
  });
}

// ── CSV extraction from HTML template ──

function extractCsvFromHtml(html) {
  const match = html.match(/<template\s+id="uaf-payload-csv"[^>]*>([\s\S]*?)<\/template>/);
  if (!match) throw new Error("Could not find uaf-payload-csv template in HTML");
  return match[1].trim();
}

// ── Main ──

async function main() {
  const browser = await findBrowser();
  if (!browser) {
    throw new Error("No Chrome or Edge executable found. Set CHROME_PATH or install a browser.");
  }
  console.log(`Using browser: ${browser}`);

  // Import pdf-lib from local node_modules (installed in ark-pdf-gen/)
  const { PDFDocument, AFRelationship } = await import("./ark-pdf-gen/node_modules/pdf-lib/dist/pdf-lib.esm.min.js");

  for (const style of STYLES) {
    const htmlPath = join(stylesDir, `${style}.html`);
    const pdfPath = join(stylesDir, `${style}.pdf`);

    // Read HTML
    const html = await readFile(htmlPath, "utf-8");

    // Convert HTML → PDF via browser
    const tempDir = await mkdtemp(join(tmpdir(), "uaf-ark-"));
    const tempPdf = join(tempDir, "raw.pdf");
    try {
      await htmlToPdfFile(browser, htmlPath, tempPdf);
      const pdfBytes = await readFile(tempPdf);

      // Extract CSV payload
      const csv = extractCsvFromHtml(html);
      const csvBytes = new TextEncoder().encode(csv);

      // Embed CSV as PDF attachment
      const pdfDoc = await PDFDocument.load(pdfBytes);
      if (pdfDoc.getPageCount() < 1) {
        throw new Error(`${style}.pdf has 0 pages`);
      }
      await pdfDoc.attach(csvBytes, "uaf_payload.csv", {
        mimeType: "text/csv",
        description: "UAF v1.0 payload",
        afRelationship: AFRelationship.Data,
        creationDate: new Date(),
        modificationDate: new Date(),
      });

      const finalBytes = await pdfDoc.save({ useObjectStreams: false });
      await writeFile(pdfPath, finalBytes);
      console.log(`  ✓ ${style}.pdf (${(finalBytes.length / 1024).toFixed(1)} KB, ${pdfDoc.getPageCount()} page(s))`);
    } finally {
      await rm(tempDir, { recursive: true, force: true });
    }
  }

  console.log(`\nDone. Generated ${STYLES.length} PDFs in ${stylesDir}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
