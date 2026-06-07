import { serializePayload, type UafPayload } from "@uaf/core";

export interface RenderHtmlOptions {
  /** Display date in Chinese ("YYYY年M月D日") or keep ISO format. Defaults to "zh". */
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

function formatDateZh(dateStr: string): string {
  const d = new Date(dateStr);
  if (Number.isNaN(d.getTime())) return dateStr;
  const year = d.getFullYear();
  const month = d.getMonth() + 1;
  const day = d.getDate();
  return `${year}年${month}月${day}日`;
}

function formatDate(dateStr: string, mode: "zh" | "iso"): string {
  return mode === "zh" ? formatDateZh(dateStr) : dateStr;
}

function renderTags(tags: string[]): string {
  if (tags.length === 0) return "";
  const chips = tags
    .map((tag) => `<span class="tag-chip">${escapeHtml(tag)}</span>`)
    .join("");
  return `<div class="tags">${chips}</div>`;
}

function renderContent(content: string): string {
  // Preserve line breaks as <br> while escaping HTML
  return content
    .split("\n")
    .map((line) => escapeHtml(line))
    .join("<br>");
}

/**
 * Render a UAF payload into a self-contained HTML document string.
 *
 * The returned HTML is a complete, standalone document with all CSS inlined.
 * It is designed to be printed directly from a modern browser to A4 PDF.
 */
export function renderUafHtml(payload: UafPayload, options?: RenderHtmlOptions): string {
  const dateDisplay = options?.dateDisplay ?? "zh";
  const subject = escapeHtml(payload.subject);
  const date = escapeHtml(formatDate(payload.date, dateDisplay));
  const content = renderContent(payload.content);
  const tagsHtml = renderTags(payload.tags);
  const payloadCsv = escapeHtml(serializePayload(payload));

  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>UAF - ${subject}</title>
<style>
@page {
  size: A4 portrait;
  margin: 0;
}

@media print {
  body {
    margin: 0;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
}

* {
  box-sizing: border-box;
}

html, body {
  margin: 0;
  padding: 0;
}

body {
  width: 210mm;
  min-height: 297mm;
  background: #F8FAFC;
  font-family: "Noto Sans SC", "PingFang SC", "Microsoft YaHei", "Hiragino Sans GB", "WenQuanYi Micro Hei", sans-serif;
  color: #0F172A;
  position: relative;
  padding: 40pt;
}

.card {
  background: #FFFFFF;
  border: 1pt solid #E2E8F0;
  border-radius: 16pt;
  box-shadow: 0 2pt 8pt rgba(148, 163, 184, 0.15);
  width: 100%;
  padding: 24pt;
}

.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 16pt;
}

.subject-pill {
  display: inline-block;
  background: #2563EB;
  color: #FFFFFF;
  font-size: 14pt;
  line-height: 1;
  padding: 8pt 16pt;
  border-radius: 9999pt;
  font-weight: 500;
}

.date-pill {
  display: inline-block;
  background: #F1F5F9;
  color: #334155;
  font-size: 12pt;
  line-height: 1;
  padding: 6pt 12pt;
  border-radius: 9999pt;
}

.divider {
  height: 1pt;
  background: #E2E8F0;
  margin-bottom: 20pt;
}

.content {
  font-size: 22pt;
  line-height: 1.5;
  color: #0F172A;
  word-wrap: break-word;
  overflow-wrap: break-word;
}

.tags {
  display: flex;
  flex-wrap: wrap;
  gap: 8pt;
  margin-top: 20pt;
}

.tag-chip {
  display: inline-block;
  background: #E0E7FF;
  color: #3730A3;
  font-size: 11pt;
  line-height: 1;
  padding: 5pt 10pt;
  border-radius: 9999pt;
}

.watermark {
  position: absolute;
  right: 40pt;
  bottom: 40pt;
  font-size: 10pt;
  color: #94A3B8;
  opacity: 0.5;
  pointer-events: none;
  user-select: none;
}
</style>
</head>
<body>
<div class="card">
  <div class="header">
    <span class="subject-pill">${subject}</span>
    <span class="date-pill">${date}</span>
  </div>
  <div class="divider"></div>
  <div class="content">${content}</div>
  ${tagsHtml}
</div>
<div class="watermark">使用 UAF v1.0 导出</div>
<template id="uaf-payload-csv" data-filename="uaf_payload.csv">${payloadCsv}</template>
</body>
</html>`;
}
