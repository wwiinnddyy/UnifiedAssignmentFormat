import { describe, expect, it } from "vitest";
import type { UafDocument } from "@uaf/core";
import { renderUafHtml } from "./renderHtml.js";

const document: UafDocument = [
  { subject: "Math & Geometry", date: "2026-05-19", content: "Work <script>\nSecond line", tags: ["A&B"] },
  { subject: "Chinese", date: "2026-05-19", content: "Read the poem", tags: [] },
];

describe("renderUafHtml", () => {
  it("renders a self-contained multi-card A4 document", () => {
    const html = renderUafHtml(document);
    expect(html).toContain("grid-template-columns: repeat(2");
    expect(html.match(/<article class="card">/g)).toHaveLength(2);
    expect(html).toContain("使用 UAF v1.0 导出");
    expect(html).not.toMatch(/<link\b|<script\b|\bsrc\s*=/i);
  });

  it("escapes every assignment and embeds the complete CSV", () => {
    const html = renderUafHtml(document);
    expect(html).toContain("Math &amp; Geometry");
    expect(html).toContain("Work &lt;script&gt;<br>Second line");
    expect(html).toContain("Math &amp; Geometry,2026-05-19");
  });

  it("splits long content into continuation cards without dropping payload text", () => {
    const longDocument: UafDocument = [{ ...document[0], content: "x".repeat(1100) }];
    const html = renderUafHtml(longDocument);
    expect(html.match(/<article class="card">/g)).toHaveLength(3);
    expect(html).toContain("（续）");
    expect(html).toContain("x".repeat(1100));
  });
});
