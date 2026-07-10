import { describe, expect, it } from "vitest";
import { UafError, UafErrorCode, type UafDocument } from "@uaf/core";
import { renderUafHtml } from "./renderHtml.js";
import { extractUafPayloadCsvFromHtml, extractUafPayloadFromHtml } from "./extractUafHtml.js";

const document: UafDocument = [
  { subject: "Math & Geometry", date: "2026-05-19", content: "Work", tags: ["required"] },
  { subject: "English", date: "2026-05-19", content: "Read", tags: [] },
];

describe("extractUafPayloadFromHtml", () => {
  it("restores all assignments", () => {
    const html = renderUafHtml(document);
    expect(extractUafPayloadFromHtml(html)).toEqual(document);
    expect(extractUafPayloadCsvFromHtml(html)).toContain("English");
  });

  it("reports missing payload templates", () => {
    try {
      extractUafPayloadFromHtml("<!DOCTYPE html><html></html>");
      throw new Error("Expected extraction to fail");
    } catch (error) {
      expect(error).toBeInstanceOf(UafError);
      expect((error as UafError).code).toBe(UafErrorCode.NoPayload);
    }
  });
});
