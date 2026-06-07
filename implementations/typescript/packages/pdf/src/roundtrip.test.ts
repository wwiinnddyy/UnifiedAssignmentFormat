import { describe, expect, it } from "vitest";
import type { UafPayload } from "@uaf/core";
import { PDFArray, PDFDocument, PDFRawStream, PDFStream, decodePDFRawStream } from "pdf-lib";
import { createUafPdf } from "./createUafPdf.js";
import { extractUafPayload } from "./extractUafPayload.js";
import { collectPdfText, loadChineseFontForText } from "./font.js";

const payload: UafPayload = {
  subject: "Math",
  date: "2026-05-19",
  content: "Complete exercises 1-2 on page 45.",
  tags: ["required"],
};

const chinesePayload: UafPayload = {
  subject: "数学",
  date: "2026-05-19",
  content: "完成课本第45页第1、2题，请拍照上传。",
  tags: ["必做", "几何"],
};

async function getFirstPageContent(pdf: Uint8Array): Promise<string> {
  const doc = await PDFDocument.load(pdf);
  const page = doc.getPage(0);
  const contents = page.node.Contents();
  const objects = contents instanceof PDFArray
    ? Array.from({ length: contents.size() }, (_, i) => doc.context.lookup(contents.get(i)))
    : contents
      ? [doc.context.lookup(contents)]
      : [];

  const bytes = objects.flatMap((object) => {
    if (object instanceof PDFRawStream) {
      return Array.from(decodePDFRawStream(object).decode());
    }
    if (object instanceof PDFStream) {
      return Array.from(object.getContents());
    }
    return [];
  });

  return new TextDecoder("latin1").decode(new Uint8Array(bytes));
}

describe("@uaf/pdf round-trip", () => {
  it("embeds and extracts uaf_payload.csv", async () => {
    const pdf = await createUafPdf(payload, { useStandardFont: true });
    expect(pdf.length).toBeGreaterThan(1000);
    const extracted = await extractUafPayload(pdf);
    expect(extracted).toEqual(payload);
  });

  it("produces compact PDF with subset CJK font", async () => {
    const pdf = await createUafPdf(chinesePayload);
    expect(pdf.length).toBeLessThan(500_000);
    const extracted = await extractUafPayload(pdf);
    expect(extracted).toEqual(chinesePayload);
  });

  it("builds a PDF-renderable SFNT subset instead of WOFF2", async () => {
    const fontBytes = await loadChineseFontForText(collectPdfText(chinesePayload));
    expect(Array.from(fontBytes.slice(0, 4))).toEqual([0x00, 0x01, 0x00, 0x00]);
    expect(new TextDecoder("latin1").decode(fontBytes.slice(0, 4))).not.toBe("wOF2");
    expect(fontBytes.length).toBeLessThan(200_000);
  });

  it("renders a visible assignment module on the PDF page", async () => {
    const pdf = await createUafPdf(chinesePayload);
    const doc = await PDFDocument.load(pdf);
    expect(doc.getPageCount()).toBe(1);

    const content = await getFirstPageContent(pdf);
    expect(content.length).toBeGreaterThan(2_000);
    expect(content.match(/\bBT\b/g)?.length ?? 0).toBeGreaterThanOrEqual(6);
    expect(content.match(/\brg\b/g)?.length ?? 0).toBeGreaterThanOrEqual(6);
    expect(content).toContain("0.12156862745098039 0.19215686274509805 0.27450980392156865 rg");
  });
});
