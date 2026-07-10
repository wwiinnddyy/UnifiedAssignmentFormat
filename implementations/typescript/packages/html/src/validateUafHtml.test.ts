import { describe, expect, it } from "vitest";
import type { UafDocument } from "@uaf/core";
import { renderUafHtml } from "./renderHtml.js";
import { validateUafHtml } from "./validateUafHtml.js";

const document: UafDocument = [
  { subject: "Math", date: "2026-05-19", content: "Work", tags: [] },
  { subject: "English", date: "2026-05-19", content: "Read", tags: [] },
];

describe("validateUafHtml", () => {
  it("accepts the multi-card renderer output", () => {
    expect(validateUafHtml(renderUafHtml(document))).toMatchObject({ valid: true, payload: document });
  });

  it("rejects ordinary HTML", () => {
    expect(validateUafHtml("<html></html>").valid).toBe(false);
  });
});
