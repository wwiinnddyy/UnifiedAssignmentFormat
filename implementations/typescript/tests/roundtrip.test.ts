import { parsePayload, serializePayload, type UafDocument } from "@uaf/core";
import { createUafPdf, extractUafPayload, validateUafPdf } from "@uaf/pdf";
import { describe, expect, it } from "vitest";

const document: UafDocument = [
  { subject: "Math", date: "2026-05-19", content: "Exercises", tags: [] },
  { subject: "English", date: "2026-05-19", content: "Read Unit 3", tags: ["reading"] },
];

describe("UAF integration", () => {
  it("round-trips CSV and PDF documents", async () => {
    expect(parsePayload(serializePayload(document))).toEqual(document);
    const pdf = await createUafPdf(document, { useStandardFont: true });
    expect(await extractUafPayload(pdf)).toEqual(document);
    expect((await validateUafPdf(pdf)).valid).toBe(true);
  });
});
