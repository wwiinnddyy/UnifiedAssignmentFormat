import { describe, expect, it } from "vitest";
import { serializePayload, type UafDocument } from "@uaf/core";
import { createUafHtml, createUafHtmlFromCsv } from "./createUafHtml.js";

const document: UafDocument = [
  { subject: "Math", date: "2026-05-19", content: "Exercises 1 and 2", tags: ["required"] },
  { subject: "English", date: "2026-05-19", content: "Read Unit 3", tags: [] },
];

describe("createUafHtml", () => {
  it("validates and renders all assignments", () => {
    const html = createUafHtml(document);
    expect(html).toContain("Math");
    expect(html).toContain("English");
  });

  it("parses multi-row CSV before rendering", () => {
    const html = createUafHtmlFromCsv(serializePayload(document), { dateDisplay: "iso" });
    expect(html.match(/2026-05-19/g)?.length).toBeGreaterThanOrEqual(2);
  });
});
