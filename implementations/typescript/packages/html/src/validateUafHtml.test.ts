import { describe, expect, it } from "vitest";
import type { UafPayload } from "@uaf/core";
import { createUafHtml } from "./createUafHtml.js";
import { validateUafHtml } from "./validateUafHtml.js";

const payload: UafPayload = {
  subject: "数学",
  date: "2026-05-19",
  content: "完成课本第45页第1、2题，请拍照上传。",
  tags: ["必做", "几何"],
};

describe("validateUafHtml", () => {
  it("returns the embedded payload for valid UAF HTML", () => {
    const result = validateUafHtml(createUafHtml(payload));

    expect(result.valid).toBe(true);
    expect(result.payload).toEqual(payload);
    expect(result.errors).toEqual([]);
  });

  it("returns validation errors for HTML without an embedded payload", () => {
    const result = validateUafHtml("<!DOCTYPE html><html></html>");

    expect(result.valid).toBe(false);
    expect(result.payload).toBeUndefined();
    expect(result.errors[0]).toContain("uaf-payload-csv");
  });

  it("rejects HTML with external assets or scripts", () => {
    const html = createUafHtml(payload).replace(
      "</head>",
      '<link rel="stylesheet" href="theme.css"></head>',
    );
    const result = validateUafHtml(html);

    expect(result.valid).toBe(false);
    expect(result.payload).toBeUndefined();
    expect(result.errors).toContain(
      "HTML must stay self-contained without external assets or scripts",
    );
  });

  it("rejects HTML that is missing printable A4 CSS", () => {
    const html = createUafHtml(payload)
      .replace("@page", "@media screen")
      .replace("size: A4 portrait", "size: letter");
    const result = validateUafHtml(html);

    expect(result.valid).toBe(false);
    expect(result.payload).toBeUndefined();
    expect(result.errors).toContain("HTML must define @page print CSS");
    expect(result.errors).toContain("HTML print CSS must set size: A4 portrait");
  });

  it("rejects HTML whose payload template does not name the CSV attachment", () => {
    const html = createUafHtml(payload).replace(
      ' data-filename="uaf_payload.csv"',
      "",
    );
    const result = validateUafHtml(html);

    expect(result.valid).toBe(false);
    expect(result.payload).toBeUndefined();
    expect(result.errors).toContain(
      'HTML payload template must declare data-filename="uaf_payload.csv"',
    );
  });
});
