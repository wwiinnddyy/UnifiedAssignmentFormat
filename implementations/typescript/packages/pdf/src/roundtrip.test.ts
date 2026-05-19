import { describe, expect, it } from "vitest";
import type { UafPayload } from "@uaf/core";
import { createUafPdf } from "./createUafPdf.js";
import { extractUafPayload } from "./extractUafPayload.js";
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
});
