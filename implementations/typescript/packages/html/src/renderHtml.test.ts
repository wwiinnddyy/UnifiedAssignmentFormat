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
    expect(html).toContain(`.tags {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));`);
    expect(html).toContain("max-width: 100%;");
    expect(html).toContain("overflow-wrap: anywhere;");
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
    expect(html.match(/<article class="card">/g)?.length).toBeGreaterThan(3);
    expect(html).toContain("（续）");
    expect(html).toContain("x".repeat(1100));
  });

  it("splits twenty tags into lossless two-row continuation cards", () => {
    const tags = Array.from({ length: 20 }, (_, index) => `tag-${index.toString().padStart(2, "0")}`);
    const taggedDocument: UafDocument = [
      {
        subject: "Projects",
        date: "2026-05-19",
        content: "Complete the project log.",
        tags,
      },
    ];

    const html = renderUafHtml(taggedDocument);
    const cards = [...html.matchAll(/<article class="card">([\s\S]*?)<\/article>/g)];
    const tagContainers = [...html.matchAll(/<div class="tags">([\s\S]*?)<\/div>/g)];
    const renderedTags = cards.flatMap((card) => [
      ...card[1].matchAll(/<span class="tag-chip">([^<]*)<\/span>/g),
    ]).map((match) => match[1]);

    expect(cards).toHaveLength(5);
    expect(tagContainers).toHaveLength(5);
    for (const container of tagContainers) {
      expect(container[1].match(/class="tag-chip"/g)).toHaveLength(4);
    }
    expect(renderedTags).toEqual(tags);
    expect(html.match(/标签下页继续/g)).toHaveLength(4);
    expect(html).toContain("Projects（续）");
    expect(html).toContain(tags.join(";"));
  });

  it("does not split a surrogate pair at a continuation boundary", () => {
    const content = `${"x".repeat(149)}😀${"y".repeat(20)}`;
    const html = renderUafHtml([{ ...document[0], content }]);
    const renderedContent = [...html.matchAll(/<div class="content">([\s\S]*?)<\/div>/g)]
      .map((match) => match[1])
      .join("");

    expect(renderedContent).toBe(content);
  });
});
