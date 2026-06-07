import { describe, expect, it } from "vitest";
import type { UafPayload } from "@uaf/core";
import { renderUafHtml } from "./renderHtml.js";

const payload: UafPayload = {
  subject: "数学 & 几何",
  date: "2026-05-19",
  content: "完成 <script>\n第二行 & more",
  tags: ["必做", "A&B"],
};

describe("renderUafHtml", () => {
  it("renders a self-contained printable A4 HTML document", () => {
    const html = renderUafHtml(payload);

    expect(html).toContain("<!DOCTYPE html>");
    expect(html).toContain('<html lang="zh-CN">');
    expect(html).toContain("@page");
    expect(html).toContain("size: A4 portrait");
    expect(html).toContain("print-color-adjust: exact");
    expect(html).toContain("border-radius: 16pt");
    expect(html).toContain("box-shadow: 0 2pt 8pt rgba(148, 163, 184, 0.15)");
    expect(html).toContain("使用 UAF v1.0 导出");
    expect(html).toContain('id="uaf-payload-csv"');
    expect(html).toContain('data-filename="uaf_payload.csv"');
    expect(html).not.toMatch(/<link\b|<script\b|src=/i);
  });

  it("escapes payload text and preserves content line breaks", () => {
    const html = renderUafHtml(payload);

    expect(html).toContain("数学 &amp; 几何");
    expect(html).toContain("完成 &lt;script&gt;<br>第二行 &amp; more");
    expect(html).toContain('<span class="tag-chip">A&amp;B</span>');
    expect(html).toContain("完成 &lt;script&gt;\n第二行 &amp; more");
  });

  it("formats dates for display without changing the payload contract", () => {
    expect(renderUafHtml(payload)).toContain("2026年5月19日");
    expect(renderUafHtml(payload, { dateDisplay: "iso" })).toContain("2026-05-19");
  });

  it("omits the tag container when there are no tags", () => {
    const html = renderUafHtml({ ...payload, tags: [] });

    expect(html).not.toContain('<div class="tags">');
  });
});
