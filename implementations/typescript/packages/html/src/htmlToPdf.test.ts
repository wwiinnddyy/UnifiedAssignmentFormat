import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PDFDocument } from "pdf-lib";
import { describe, expect, it } from "vitest";
import type { UafPayload } from "@uaf/core";
import { extractUafPayload } from "@uaf/pdf";
import { createUafPdfFromHtml } from "./createUafPdf.js";
import { htmlToPdf } from "./htmlToPdf.js";

describe("htmlToPdf", () => {
  it("prints HTML with injected browser settings and leaves the browser open", async () => {
    const calls: {
      html?: string;
      waitUntil?: string;
      pdfOptions?: unknown;
      pageClosed?: boolean;
      browserClosed?: boolean;
    } = {};
    const browser = {
      async newPage() {
        return {
          async setContent(html: string, options: { waitUntil: string }) {
            calls.html = html;
            calls.waitUntil = options.waitUntil;
          },
          async pdf(options: unknown) {
            calls.pdfOptions = options;
            return new Uint8Array([1, 2, 3]);
          },
          async close() {
            calls.pageClosed = true;
          },
        };
      },
      async close() {
        calls.browserClosed = true;
      },
    };

    const pdf = await htmlToPdf("<html><body>OK</body></html>", {
      browser,
      width: "100mm",
      height: "200mm",
      printBackground: false,
      waitUntil: "load",
    });

    expect(Array.from(pdf)).toEqual([1, 2, 3]);
    expect(calls.html).toBe("<html><body>OK</body></html>");
    expect(calls.waitUntil).toBe("load");
    expect(calls.pdfOptions).toEqual({
      width: "100mm",
      height: "200mm",
      printBackground: false,
      preferCSSPageSize: true,
    });
    expect(calls.pageClosed).toBe(true);
    expect(calls.browserClosed).toBeUndefined();
  });

  it("can print with an explicit browser executable fallback", async () => {
    const baseDoc = await PDFDocument.create();
    baseDoc.addPage([595.28, 841.89]);
    const pdfBase64 = Buffer.from(await baseDoc.save()).toString("base64");
    const tempDir = await mkdtemp(join(tmpdir(), "uaf-fake-browser-"));
    const scriptPath = join(tempDir, "fake-browser.mjs");

    await writeFile(
      scriptPath,
      `
import { writeFileSync } from "node:fs";

const targetArg = process.argv.find((arg) => arg.startsWith("--print-to-pdf="));
if (!targetArg) {
  process.exit(2);
}

writeFileSync(targetArg.slice("--print-to-pdf=".length), Buffer.from("${pdfBase64}", "base64"));
`,
      "utf-8",
    );

    try {
      const pdf = await htmlToPdf("<html><body>OK</body></html>", {
        browserExecutablePath: process.execPath,
        browserArgs: [scriptPath],
      });
      const printed = await PDFDocument.load(pdf);

      expect(printed.getPageCount()).toBe(1);
    } finally {
      await rm(tempDir, { recursive: true, force: true });
    }
  });
});

describe("createUafPdfFromHtml", () => {
  it("prints rendered HTML to PDF and attaches the UAF payload CSV", async () => {
    const baseDoc = await PDFDocument.create();
    baseDoc.addPage([595.28, 841.89]);
    const printedPdf = await baseDoc.save();
    let printedHtml = "";

    const browser = {
      async newPage() {
        return {
          async setContent(html: string) {
            printedHtml = html;
          },
          async pdf() {
            return printedPdf;
          },
          async close() {
            // no-op
          },
        };
      },
      async close() {
        // no-op
      },
    };
    const payload: UafPayload = {
      subject: "数学",
      date: "2026-05-19",
      content: "完成课本第45页第1、2题，请拍照上传。",
      tags: ["必做", "几何"],
    };

    const pdf = await createUafPdfFromHtml(payload, { browser });
    const resultDoc = await PDFDocument.load(pdf);

    expect(resultDoc.getPageCount()).toBe(1);
    expect(printedHtml).toContain("border-radius: 16pt");
    expect(printedHtml).toContain("数学");
    expect(await extractUafPayload(pdf)).toEqual(payload);
  });

  it("rejects multi-page browser output", async () => {
    const baseDoc = await PDFDocument.create();
    baseDoc.addPage([595.28, 841.89]);
    baseDoc.addPage([595.28, 841.89]);
    const printedPdf = await baseDoc.save();
    const payload: UafPayload = {
      subject: "Math",
      date: "2026-05-19",
      content: "Complete page 45 exercises 1-2.",
      tags: ["required"],
    };
    const browser = {
      async newPage() {
        return {
          async setContent() {
            // no-op
          },
          async pdf() {
            return printedPdf;
          },
          async close() {
            // no-op
          },
        };
      },
      async close() {
        // no-op
      },
    };

    await expect(createUafPdfFromHtml(payload, { browser })).rejects.toThrow(
      "exactly one page",
    );
  });
});
