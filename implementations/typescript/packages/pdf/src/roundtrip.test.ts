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

describe("@uaf/pdf round-trip", () => {
  it("embeds and extracts uaf_payload.csv", async () => {
    const pdf = await createUafPdf(payload, { useStandardFont: true });
    expect(pdf.length).toBeGreaterThan(1000);
    const extracted = await extractUafPayload(pdf);
    expect(extracted).toEqual(payload);
  });
});
