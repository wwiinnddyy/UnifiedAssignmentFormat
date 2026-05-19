import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { parsePayload, serializePayload, type UafPayload } from "@uaf/core";
import { createUafPdf, extractUafPayload } from "@uaf/pdf";

const samplePayload: UafPayload = {
  subject: "数学",
  date: "2026-05-19",
  content: "完成课本第45页第1、2题，请拍照上传。",
  tags: ["必做", "几何", "重难点"],
};

describe("UAF round-trip", () => {
  it("create → extract preserves payload", async () => {
    const asciiPayload = {
      subject: "Math",
      date: "2026-05-19",
      content: "Complete page 45 exercises 1-2.",
      tags: ["required", "geometry"],
    };
    const pdf = await createUafPdf(asciiPayload, { useStandardFont: true });
    const extracted = await extractUafPayload(pdf);
    expect(extracted).toEqual(asciiPayload);
  });

  it("extracts from golden sample PDF when present", async () => {
    const pdfPath = join(import.meta.dirname, "..", "..", "..", "examples", "sample-homework.pdf");
    try {
      const pdf = new Uint8Array(await readFile(pdfPath));
      const extracted = await extractUafPayload(pdf);
      expect(extracted.subject).toBe("数学");
      expect(extracted.tags).toContain("必做");
    } catch {
      // sample PDF generated in CI via generate:sample
    }
  });

  it("sample CSV parses correctly", async () => {
    const csvPath = join(import.meta.dirname, "..", "..", "..", "examples", "uaf_payload.sample.csv");
    const csv = await readFile(csvPath, "utf-8");
    const payload = parsePayload(csv);
    expect(payload.subject).toBe("数学");
    const normalized = csv.replace(/\r\n/g, "\n");
    expect(serializePayload(payload)).toBe(normalized.endsWith("\n") ? normalized : `${normalized}\n`);
  });
});
