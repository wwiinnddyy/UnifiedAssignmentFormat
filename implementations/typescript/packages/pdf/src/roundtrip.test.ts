import { PDFDocument } from "pdf-lib";
import { describe, expect, it } from "vitest";
import type { UafDocument } from "@uaf/core";
import { createUafPdf } from "./createUafPdf.js";
import { extractUafPayload } from "./extractUafPayload.js";

const document: UafDocument = [
  { subject: "Math", date: "2026-05-19", content: "Exercises 1 and 2", tags: ["required"] },
  { subject: "English", date: "2026-05-19", content: "Read Unit 3", tags: [] },
  { subject: "Science", date: "2026-05-19", content: "Lab notes", tags: ["lab"] },
];

describe("UAF PDF multi-assignment round-trip", () => {
  it("embeds and restores all assignments in order", async () => {
    const bytes = await createUafPdf(document, { useStandardFont: true });
    expect(await extractUafPayload(bytes)).toEqual(document);
  });

  it("adds pages when card fragments exceed one page", async () => {
    const assignments = Array.from({ length: 12 }, (_, index) => ({
      subject: `Subject ${index + 1}`,
      date: "2026-05-19",
      content: "Work ".repeat(90),
      tags: [],
    }));
    const large: UafDocument = [assignments[0], ...assignments.slice(1)];
    const bytes = await createUafPdf(large, { useStandardFont: true });
    const pdf = await PDFDocument.load(bytes);
    expect(pdf.getPageCount()).toBeGreaterThan(1);
    expect(await extractUafPayload(bytes)).toEqual(large);
  });
});
