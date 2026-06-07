import type { PDFPage, PDFFont, RGB } from "pdf-lib";
import { rgb } from "pdf-lib";
import type { UafPayload } from "@uaf/core";
import { drawPill, drawRoundedRect } from "./drawShapes.js";

export const PAGE_WIDTH = 595.28;
export const PAGE_HEIGHT = 841.89;

const PAGE_MARGIN = 40;
const TILE_W = 260;
const TILE_H = 260;
const TILE_RADIUS = 16;
const TILE_PAD = 15;
const SUBJECT_H = 62;
const TAGS_H = 54;
const CONTENT_GAP = 10;

const SUBJECT_FONT = 20;
const DATE_FONT = 10;
const CONTENT_SIZES = [16, 14.5, 13];
const TAG_FONT = 10;
const WATERMARK_FONT = 9;

const COLORS = {
  pageBg: rgb(244 / 255, 247 / 255, 250 / 255),
  tileShadow: rgb(196 / 255, 206 / 255, 218 / 255),
  tileBorder: rgb(42 / 255, 55 / 255, 71 / 255),
  tileBg: rgb(255 / 255, 255 / 255, 255 / 255),
  subjectBg: rgb(31 / 255, 49 / 255, 70 / 255),
  subjectAccent: rgb(245 / 255, 158 / 255, 11 / 255),
  subjectText: rgb(255 / 255, 255 / 255, 255 / 255),
  dateText: rgb(204 / 255, 232 / 255, 238 / 255),
  contentBg: rgb(248 / 255, 251 / 255, 252 / 255),
  contentBorder: rgb(187 / 255, 205 / 255, 216 / 255),
  contentText: rgb(20 / 255, 29 / 255, 40 / 255),
  tagsBg: rgb(255 / 255, 244 / 255, 214 / 255),
  tagsRule: rgb(222 / 255, 186 / 255, 94 / 255),
  tagChipBg: rgb(255 / 255, 252 / 255, 244 / 255),
  tagChipBorder: rgb(180 / 255, 117 / 255, 20 / 255),
  tagChipShadow: rgb(226 / 255, 196 / 255, 126 / 255),
  tagText: rgb(72 / 255, 48 / 255, 13 / 255),
  mutedText: rgb(91 / 255, 103 / 255, 116 / 255),
  watermark: rgb(114 / 255, 126 / 255, 140 / 255),
};

interface TextBlock {
  lines: string[];
  fontSize: number;
  lineHeight: number;
}

interface TagChip {
  label: string;
  w: number;
  h: number;
}

function formatDateDisplay(isoDate: string): string {
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(isoDate);
  if (dateOnly) return `${dateOnly[1]}年${Number(dateOnly[2])}月${Number(dateOnly[3])}日`;

  const d = new Date(isoDate);
  if (Number.isNaN(d.getTime())) return isoDate;
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
}

function textBaselineInBox(
  boxBottom: number,
  boxH: number,
  font: PDFFont,
  fontSize: number,
): number {
  const fontH = font.heightAtSize(fontSize);
  return boxBottom + (boxH - fontH) / 2 + fontH * 0.72;
}

function widthOf(font: PDFFont, text: string, size: number): number {
  return font.widthOfTextAtSize(text, size);
}

function ellipsize(text: string, font: PDFFont, size: number, maxW: number): string {
  if (widthOf(font, text, size) <= maxW) return text;

  let output = "";
  for (const char of text) {
    if (widthOf(font, `${output}${char}...`, size) > maxW) {
      return output.length > 0 ? `${output}...` : "...";
    }
    output += char;
  }
  return output;
}

function wrapText(text: string, font: PDFFont, size: number, maxW: number): string[] {
  const lines: string[] = [];
  let current = "";

  for (const char of text) {
    if (char === "\n") {
      lines.push(current);
      current = "";
      continue;
    }

    const next = current + char;
    if (current && widthOf(font, next, size) > maxW) {
      lines.push(current);
      current = char;
    } else {
      current = next;
    }
  }

  if (current || lines.length === 0) lines.push(current);
  return lines;
}

function fitTextBlock(text: string, font: PDFFont, maxW: number, maxH: number): TextBlock {
  for (const size of CONTENT_SIZES) {
    const lineHeight = size * 1.42;
    const lines = wrapText(text, font, size, maxW);
    if (lines.length * lineHeight <= maxH) {
      return { lines, fontSize: size, lineHeight };
    }
  }

  const fontSize = CONTENT_SIZES[CONTENT_SIZES.length - 1];
  const lineHeight = fontSize * 1.42;
  const maxLines = Math.max(1, Math.floor(maxH / lineHeight));
  const lines = wrapText(text, font, fontSize, maxW).slice(0, maxLines);
  const lastIndex = lines.length - 1;
  lines[lastIndex] = ellipsize(lines[lastIndex] ?? "", font, fontSize, maxW);
  return { lines, fontSize, lineHeight };
}

function layoutTags(tags: string[], font: PDFFont, maxW: number): TagChip[] {
  const chipH = 20;
  const chips: TagChip[] = [];
  let used = 0;

  for (const rawTag of tags) {
    const label = ellipsize(rawTag, font, TAG_FONT, maxW - 16);
    const w = Math.min(maxW, widthOf(font, label, TAG_FONT) + 18);
    if (chips.length > 0 && used + 7 + w > maxW) break;
    chips.push({ label, w, h: chipH });
    used += (chips.length > 1 ? 7 : 0) + w;
  }

  return chips;
}

function drawText(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  font: PDFFont,
  size: number,
  color: RGB,
): void {
  page.drawText(text, { x, y, font, size, color });
}

function drawStrongText(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  font: PDFFont,
  size: number,
  color: RGB,
): void {
  page.drawText(text, { x, y, font, size, color });
  page.drawText(text, { x: x + 0.16, y, font, size, color });
  page.drawText(text, { x, y: y + 0.14, font, size, color });
}

function drawTopRoundedBand(page: PDFPage, x: number, y: number, w: number, h: number): void {
  drawRoundedRect(page, x, y, w, h, TILE_RADIUS, COLORS.subjectBg);
  page.drawRectangle({
    x,
    y,
    width: w,
    height: TILE_RADIUS,
    color: COLORS.subjectBg,
  });
}

function drawAssignmentTile(
  page: PDFPage,
  payload: UafPayload,
  font: PDFFont,
  fontBold: PDFFont,
  options: { dateDisplay?: "zh" | "iso"; canRenderCjk?: boolean },
): void {
  const x = PAGE_MARGIN;
  const y = PAGE_HEIGHT - PAGE_MARGIN - TILE_H;
  const innerX = x + TILE_PAD;
  const innerW = TILE_W - TILE_PAD * 2;
  const subjectY = y + TILE_H - SUBJECT_H;
  const tagsY = y;
  const contentY = tagsY + TAGS_H + CONTENT_GAP;
  const contentH = subjectY - contentY - CONTENT_GAP;
  const dateText = options.dateDisplay === "iso" ? payload.date : formatDateDisplay(payload.date);

  drawRoundedRect(page, x + 4, y - 4, TILE_W, TILE_H, TILE_RADIUS, COLORS.tileShadow);
  drawRoundedRect(page, x, y, TILE_W, TILE_H, TILE_RADIUS, COLORS.tileBg, {
    color: COLORS.tileBorder,
    width: 1.4,
  });

  drawTopRoundedBand(page, x, subjectY, TILE_W, SUBJECT_H);
  drawRoundedRect(page, innerX, subjectY + 14, 5, SUBJECT_H - 28, 2.5, COLORS.subjectAccent);

  const headerTextX = innerX + 18;
  const headerTextW = innerW - 18;
  const subject = ellipsize(payload.subject, fontBold, SUBJECT_FONT, headerTextW);
  drawStrongText(page, subject, headerTextX, subjectY + 31, fontBold, SUBJECT_FONT, COLORS.subjectText);
  drawText(
    page,
    ellipsize(dateText, font, DATE_FONT, headerTextW),
    headerTextX,
    subjectY + 13,
    font,
    DATE_FONT,
    COLORS.dateText,
  );

  drawRoundedRect(page, innerX, contentY, innerW, contentH, 9, COLORS.contentBg, {
    color: COLORS.contentBorder,
    width: 0.9,
  });

  const textBlock = fitTextBlock(payload.content, font, innerW - 20, contentH - 22);
  let lineY = contentY + contentH - 20;
  for (const line of textBlock.lines) {
    if (lineY < contentY + 10) break;
    drawText(page, line, innerX + 10, lineY, font, textBlock.fontSize, COLORS.contentText);
    lineY -= textBlock.lineHeight;
  }

  drawRoundedRect(page, x, tagsY, TILE_W, TAGS_H, TILE_RADIUS, COLORS.tagsBg);
  page.drawRectangle({
    x,
    y: tagsY + TAGS_H - TILE_RADIUS,
    width: TILE_W,
    height: TILE_RADIUS,
    color: COLORS.tagsBg,
  });
  page.drawLine({
    start: { x: x + 1.5, y: tagsY + TAGS_H },
    end: { x: x + TILE_W - 1.5, y: tagsY + TAGS_H },
    thickness: 1,
    color: COLORS.tagsRule,
  });

  const tags = layoutTags(payload.tags, font, innerW);
  if (tags.length === 0) {
    const label = options.canRenderCjk === false ? "No tags" : "未标记";
    drawText(page, label, innerX, tagsY + 18, font, TAG_FONT, COLORS.mutedText);
    return;
  }

  let tagX = innerX;
  for (const chip of tags) {
    drawPill(page, tagX + 1, tagsY + 12, chip.w, chip.h, COLORS.tagChipShadow);
    drawPill(page, tagX, tagsY + 13, chip.w, chip.h, COLORS.tagChipBg, {
      color: COLORS.tagChipBorder,
      width: 0.8,
    });
    drawStrongText(
      page,
      chip.label,
      tagX + 9,
      textBaselineInBox(tagsY + 13, chip.h, font, TAG_FONT),
      font,
      TAG_FONT,
      COLORS.tagText,
    );
    tagX += chip.w + 7;
  }
}

export function renderAssignmentCard(
  page: PDFPage,
  payload: UafPayload,
  font: PDFFont,
  fontBold: PDFFont,
  options: { dateDisplay?: "zh" | "iso"; canRenderCjk?: boolean } = {},
): void {
  page.drawRectangle({
    x: 0,
    y: 0,
    width: PAGE_WIDTH,
    height: PAGE_HEIGHT,
    color: COLORS.pageBg,
  });

  drawAssignmentTile(page, payload, font, fontBold, options);

  const watermarkText = options.canRenderCjk === false ? "Exported with UAF" : "使用 UAF 导出";
  const watermarkW = widthOf(font, watermarkText, WATERMARK_FONT);
  page.drawText(watermarkText, {
    x: PAGE_WIDTH - PAGE_MARGIN - watermarkW,
    y: PAGE_MARGIN,
    size: WATERMARK_FONT,
    font,
    color: COLORS.watermark,
  });
}
