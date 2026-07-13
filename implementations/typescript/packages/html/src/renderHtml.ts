import { serializePayload, type UafAssignment, type UafDocument } from "@uaf/core";

export interface RenderHtmlOptions {
  dateDisplay?: "zh" | "iso";
}

const TAGS_PER_CARD = 4;

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
  const match = /^([+-]?\d{4,6})-(\d{2})-(\d{2})(?:$|[Tt ])/.exec(date);
  if (!match) return date;
  return `${match[1]}年${Number(match[2])}月${Number(match[3])}日`;
}

function splitContent(content: string, limit = 150, maxLineBreaks = 14): string[] {
  const normalized = content.replace(/\r\n?/g, "\n");
  const chunks: string[] = [];
  let cursor = 0;
  while (cursor < normalized.length) {
    let end = Math.min(cursor + limit, normalized.length);
    end = avoidSplittingSurrogatePair(normalized, cursor, end);
    let endedAtLineLimit = false;
    let lineBreaks = 0;
    for (let index = cursor; index < end; index++) {
      if (normalized.charCodeAt(index) !== 0x0a) continue;
      lineBreaks++;
      if (lineBreaks === maxLineBreaks) {
        end = index + 1;
        endedAtLineLimit = true;
        break;
      }
    }
    if (!endedAtLineLimit && end < normalized.length) {
      const breakAt = normalized.lastIndexOf("\n", end - 1);
      if (breakAt > cursor + Math.floor(limit / 2)) end = breakAt + 1;
    }
    chunks.push(normalized.slice(cursor, end));
    cursor = end;
  }
  return chunks.length > 0 ? chunks : [""];
}

function avoidSplittingSurrogatePair(text: string, cursor: number, end: number): number {
  if (end <= cursor || end >= text.length) return end;
  const previous = text.charCodeAt(end - 1);
  const next = text.charCodeAt(end);
  const previousIsHigh = previous >= 0xd800 && previous <= 0xdbff;
  const nextIsLow = next >= 0xdc00 && next <= 0xdfff;
  return previousIsHigh && nextIsLow ? end - 1 : end;
}

function groupTags(tags: string[]): string[][] {
  const groups: string[][] = [];
  for (let index = 0; index < tags.length; index += TAGS_PER_CARD) {
    groups.push(tags.slice(index, index + TAGS_PER_CARD));
  }
  return groups;
}

function renderCard(
  assignment: UafAssignment,
  content: string,
  options: {
    continuation: boolean;
    tags: string[];
    continuationMessage: string | null;
    dateDisplay: "zh" | "iso";
  },
): string {
  const continuationSuffix = options.continuation ? "（续）" : "";
  const subject = `${escapeHtml(assignment.subject)}${continuationSuffix}`;
  const date = escapeHtml(formatDate(assignment.date, options.dateDisplay));
  const body = content.split("\n").map(escapeHtml).join("<br>");

  let footer = "";
  if (options.tags.length > 0) {
    const tags = options.tags
      .map((tag) => `<span class="tag-chip">${escapeHtml(tag)}</span>`)
      .join("");
    footer += `\n  <div class="tags">${tags}</div>`;
  }
  if (options.continuationMessage !== null) {
    footer += `\n  <div class="continued">${escapeHtml(options.continuationMessage)}</div>`;
  }

  return `<article class="card">
  <header class="header">
    <span class="subject-pill">${subject}</span>
    <span class="date-pill">${date}</span>
  </header>
  <div class="content">${body}</div>${footer}
</article>`;
}

export function renderUafHtml(document: UafDocument, options?: RenderHtmlOptions): string {
  const dateDisplay = options?.dateDisplay ?? "zh";
  const cards: string[] = [];
  for (const assignment of document) {
    const chunks = splitContent(assignment.content);
    const tagGroups = groupTags(assignment.tags);
    for (let index = 0; index < chunks.length; index++) {
      const isLastContentChunk = index === chunks.length - 1;
      cards.push(
        renderCard(assignment, chunks[index], {
          continuation: index > 0,
          tags: isLastContentChunk && tagGroups.length > 0 ? tagGroups[0] : [],
          continuationMessage: !isLastContentChunk
            ? "正文下页继续"
            : tagGroups.length > 1
              ? "标签下页继续"
              : null,
          dateDisplay,
        }),
      );
    }
    for (let index = 1; index < tagGroups.length; index++) {
      cards.push(
        renderCard(assignment, "", {
          continuation: true,
          tags: tagGroups[index],
          continuationMessage: index < tagGroups.length - 1 ? "标签下页继续" : null,
          dateDisplay,
        }),
      );
    }
  }
  const payloadCsv = escapeHtml(serializePayload(document));

  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>UAF - 作业</title>
<style>
@page { size: A4 portrait; margin: 0; }
@media print {
  body { margin: 0; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  background: #F8FAFC;
  color: #0F172A;
  font-family: "Noto Sans SC", "PingFang SC", "Microsoft YaHei", "Hiragino Sans GB", "WenQuanYi Micro Hei", sans-serif;
}
.document {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14pt;
  align-items: start;
  padding: 40pt;
}
.card {
  break-inside: avoid;
  page-break-inside: avoid;
  background: #FFFFFF;
  border: 1pt solid #E2E8F0;
  border-radius: 16pt;
  box-shadow: 0 2pt 8pt rgba(148, 163, 184, 0.15);
  padding: 24pt;
  overflow: hidden;
}
.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12pt;
  padding-bottom: 20pt;
  border-bottom: 1pt solid #E2E8F0;
}
.subject-pill {
  display: inline-block;
  min-width: 0;
  background: #2563EB;
  color: #FFFFFF;
  font-size: 14pt;
  line-height: 1.2;
  padding: 8pt 16pt;
  border-radius: 9999pt;
  overflow-wrap: anywhere;
}
.date-pill {
  display: inline-block;
  flex: 0 0 auto;
  background: #F1F5F9;
  color: #334155;
  font-size: 12pt;
  line-height: 1.2;
  padding: 6pt 12pt;
  border-radius: 9999pt;
  white-space: nowrap;
}
.content {
  margin-top: 20pt;
  color: #0F172A;
  font-size: 22pt;
  line-height: 1.5;
  text-align: left;
  overflow-wrap: anywhere;
}
.tags {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8pt;
  margin-top: 20pt;
}
.tag-chip {
  justify-self: start;
  min-width: 0;
  max-width: 100%;
  background: #E0E7FF;
  color: #3730A3;
  font-size: 11pt;
  padding: 5pt 10pt;
  border-radius: 9999pt;
  overflow-wrap: anywhere;
}
.continued { color: #64748B; font-size: 11pt; margin-top: 20pt; }
.watermark {
  position: fixed;
  right: 40pt;
  bottom: 40pt;
  color: #94A3B8;
  opacity: 0.5;
  font-size: 10pt;
  pointer-events: none;
}
</style>
</head>
<body>
<main class="document">${cards.join("\n")}</main>
<div class="watermark">使用 UAF v1.0 导出</div>
<template id="uaf-payload-csv" data-filename="uaf_payload.csv">${payloadCsv}</template>
</body>
</html>`;
}
