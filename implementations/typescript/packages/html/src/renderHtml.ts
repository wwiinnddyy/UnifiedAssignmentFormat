import { serializePayload, type UafAssignment, type UafDocument } from "@uaf/core";

export interface RenderHtmlOptions {
  dateDisplay?: "zh" | "iso";
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function formatDate(date: string, mode: "zh" | "iso"): string {
  if (mode === "iso") return date;
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (dateOnly) return `${dateOnly[1]}年${Number(dateOnly[2])}月${Number(dateOnly[3])}日`;
  const parsed = new Date(date);
  return Number.isNaN(parsed.getTime())
    ? date
    : `${parsed.getFullYear()}年${parsed.getMonth() + 1}月${parsed.getDate()}日`;
}

function splitContent(content: string, limit = 520): string[] {
  const normalized = content.replace(/\r\n?/g, "\n");
  const chunks: string[] = [];
  let cursor = 0;
  while (cursor < normalized.length) {
    let end = Math.min(cursor + limit, normalized.length);
    if (end < normalized.length) {
      const breakAt = normalized.lastIndexOf("\n", end);
      if (breakAt > cursor + limit / 2) end = breakAt + 1;
    }
    chunks.push(normalized.slice(cursor, end));
    cursor = end;
  }
  return chunks.length > 0 ? chunks : [""];
}

function renderTags(tags: string[]): string {
  if (tags.length === 0) return "";
  return `<div class="tags">${tags
    .map((tag) => `<span class="tag-chip">${escapeHtml(tag)}</span>`)
    .join("")}</div>`;
}

function renderCard(
  assignment: UafAssignment,
  content: string,
  index: number,
  total: number,
  dateDisplay: "zh" | "iso",
): string {
  const continuation = index > 0 ? "（续）" : "";
  const tags = index === total - 1 ? renderTags(assignment.tags) : '<div class="continued">正文下页继续</div>';
  const footer = tags ? `\n  ${tags}` : "";
  return `<article class="card">
  <header class="header">
    <span class="subject-pill">${escapeHtml(assignment.subject)}${continuation}</span>
    <span class="date-pill">${escapeHtml(formatDate(assignment.date, dateDisplay))}</span>
  </header>
  <div class="content">${content.split("\n").map(escapeHtml).join("<br>")}</div>${footer}
</article>`;
}

export function renderUafHtml(document: UafDocument, options?: RenderHtmlOptions): string {
  const dateDisplay = options?.dateDisplay ?? "zh";
  const cards = document.flatMap((assignment) => {
    const chunks = splitContent(assignment.content);
    return chunks.map((content, index) => renderCard(assignment, content, index, chunks.length, dateDisplay));
  });
  const payloadCsv = escapeHtml(serializePayload(document));

  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>UAF - 作业</title>
<style>
@page { size: A4 portrait; margin: 36pt 36pt 58pt; }
@media print {
  body { margin: 0; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  .watermark { position: fixed; }
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  background: #F8FAFC;
  color: #0F172A;
  font-family: "Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif;
}
.document {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14pt;
  align-items: start;
}
.card {
  break-inside: avoid;
  background: #FFFFFF;
  border: 1pt solid #E2E8F0;
  border-radius: 16pt;
  box-shadow: 0 2pt 8pt rgba(148, 163, 184, 0.15);
  overflow: hidden;
}
.header { background: #2563EB; padding: 12pt 14pt; }
.subject-pill { display: block; color: #FFFFFF; font-size: 17pt; font-weight: 600; overflow-wrap: anywhere; }
.date-pill { display: block; color: #DBEAFE; font-size: 9.5pt; margin-top: 3pt; }
.content { padding: 16pt 14pt 12pt; font-size: 13.5pt; line-height: 1.42; overflow-wrap: anywhere; }
.tags { display: flex; flex-wrap: wrap; gap: 6pt; padding: 0 14pt 14pt; }
.tag-chip { background: #E0E7FF; color: #3730A3; font-size: 9.5pt; padding: 4pt 8pt; border-radius: 9999pt; }
.continued { color: #64748B; font-size: 9.5pt; padding: 0 14pt 14pt; }
.watermark { right: 36pt; bottom: 30pt; color: #94A3B8; opacity: .65; font-size: 9pt; }
</style>
</head>
<body>
<main class="document">${cards.join("\n")}</main>
<div class="watermark">使用 UAF v1.0 导出</div>
<template id="uaf-payload-csv" data-filename="uaf_payload.csv">${payloadCsv}</template>
</body>
</html>`;
}
