import { describe, expect, it } from "vitest";
import { serializePayload, type UafPayload } from "@uaf/core";
import { createUafHtml, createUafHtmlFromCsv } from "./createUafHtml.js";

const payload: UafPayload = {
  subject: "数学",
  date: "2026-05-19",
  content: "完成课本第45页第1、2题，请拍照上传。",
  tags: ["必做", "几何"],
};

describe("createUafHtml", () => {
  it("validates a payload and renders printable HTML", () => {
    const html = createUafHtml(payload);

    expect(html).toContain("<!DOCTYPE html>");
    expect(html).toContain("数学");
    expect(html).toContain("2026年5月19日");
  });

  it("parses CSV before rendering HTML", () => {
    const html = createUafHtmlFromCsv(serializePayload(payload), {
      dateDisplay: "iso",
    });

    expect(html).toContain("2026-05-19");
    expect(html).toContain('<span class="tag-chip">几何</span>');
  });
});
