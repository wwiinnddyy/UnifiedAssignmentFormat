import type { PDFDocument, PDFPage, PDFFont } from "pdf-lib";
import { rgb } from "pdf-lib";
import type { UafAssignment, UafDocument } from "@uaf/core";
import { drawPill, drawRoundedRect } from "./drawShapes.js";

export const PAGE_WIDTH = 595.28;
export const PAGE_HEIGHT = 841.89;

const PAGE_MARGIN = 36;
const WATERMARK_SPACE = 24;
const COLUMN_GAP = 14;
const ROW_GAP = 14;
const CARD_WIDTH = (PAGE_WIDTH - PAGE_MARGIN * 2 - COLUMN_GAP) / 2;
const CARD_PAD = 14;
const HEADER_HEIGHT = 48;
const CONTENT_FONT = 13.5;
const CONTENT_LINE_HEIGHT = 19;
const MAX_LINES_PER_FRAGMENT = 12;
const TAG_AREA_HEIGHT = 39;
const MIN_CARD_HEIGHT = 140;
const SUBJECT_FONT = 17;
const DATE_FONT = 9.5;
const TAG_FONT = 9.5;
const WATERMARK_FONT = 9;

const DEFAULT_COLORS = {
  pageBg: rgb(248 / 255, 250 / 255, 252 / 255),
  shadow: rgb(203 / 255, 213 / 255, 225 / 255),
  border: rgb(226 / 255, 232 / 255, 240 / 255),
  card: rgb(1, 1, 1),
  header: rgb(37 / 255, 99 / 255, 235 / 255),
  headerText: rgb(1, 1, 1),
  dateText: rgb(219 / 255, 234 / 255, 254 / 255),
  content: rgb(15 / 255, 23 / 255, 42 / 255),
  chip: rgb(224 / 255, 231 / 255, 255 / 255),
  chipText: rgb(55 / 255, 48 / 255, 163 / 255),
  muted: rgb(100 / 255, 116 / 255, 139 / 255),
  watermark: rgb(148 / 255, 163 / 255, 184 / 255),
};

const CLASSWORKS_DARK_COLORS: typeof DEFAULT_COLORS = {
  pageBg: rgb(18 / 255, 18 / 255, 18 / 255),
  shadow: rgb(5 / 255, 5 / 255, 5 / 255),
  border: rgb(66 / 255, 66 / 255, 66 / 255),
  card: rgb(30 / 255, 30 / 255, 30 / 255),
  header: rgb(24 / 255, 103 / 255, 192 / 255),
  headerText: rgb(1, 1, 1),
  dateText: rgb(227 / 255, 242 / 255, 253 / 255),
  content: rgb(238 / 255, 238 / 255, 238 / 255),
  chip: rgb(48 / 255, 63 / 255, 159 / 255),
  chipText: rgb(232 / 255, 234 / 255, 246 / 255),
  muted: rgb(176 / 255, 190 / 255, 197 / 255),
  watermark: rgb(144 / 255, 164 / 255, 174 / 255),
};

export type UafPdfTheme = "default" | "classworks-dark";
type ColorPalette = typeof DEFAULT_COLORS;

interface CardFragment {
  assignment: UafAssignment;
  continuation: boolean;
  lines: string[];
  showTags: boolean;
  height: number;
}

function widthOf(font: PDFFont, text: string, size: number): number {
  return font.widthOfTextAtSize(text, size);
}

function ellipsize(text: string, font: PDFFont, size: number, maxWidth: number): string {
  if (widthOf(font, text, size) <= maxWidth) return text;
  let output = "";
  for (const char of text) {
    if (widthOf(font, `${output}${char}...`, size) > maxWidth) break;
    output += char;
  }
  return `${output}...`;
}

function wrapText(text: string, font: PDFFont, size: number, maxWidth: number): string[] {
  const lines: string[] = [];
  let current = "";
  const normalized = text.replace(/\r\n?/g, "\n");
  for (const char of normalized) {
    if (char === "\n") {
      lines.push(current);
      current = "";
      continue;
    }
    if (current && widthOf(font, `${current}${char}`, size) > maxWidth) {
      lines.push(current);
      current = char;
    } else {
      current += char;
    }
  }
  if (current || lines.length === 0) lines.push(current);
  return lines;
}

function createFragments(document: UafDocument, font: PDFFont): CardFragment[] {
  const maxWidth = CARD_WIDTH - CARD_PAD * 2;
  const fragments: CardFragment[] = [];
  for (const assignment of document) {
    const lines = wrapText(assignment.content, font, CONTENT_FONT, maxWidth);
    for (let index = 0; index < lines.length; index += MAX_LINES_PER_FRAGMENT) {
      const fragmentLines = lines.slice(index, index + MAX_LINES_PER_FRAGMENT);
      const showTags = index + MAX_LINES_PER_FRAGMENT >= lines.length;
      const contentHeight = fragmentLines.length * CONTENT_LINE_HEIGHT;
      const height = Math.max(
        MIN_CARD_HEIGHT,
        CARD_PAD + HEADER_HEIGHT + 12 + contentHeight + (showTags ? TAG_AREA_HEIGHT : 12) + CARD_PAD,
      );
      fragments.push({
        assignment,
        continuation: index > 0,
        lines: fragmentLines,
        showTags,
        height,
      });
    }
  }
  return fragments;
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

function drawPageBackground(
  page: PDFPage,
  font: PDFFont,
  canRenderCjk: boolean,
  colors: ColorPalette,
): void {
  page.drawRectangle({ x: 0, y: 0, width: PAGE_WIDTH, height: PAGE_HEIGHT, color: colors.pageBg });
  const watermark = canRenderCjk ? "使用 UAF v1.0 导出" : "Exported with UAF v1.0";
  page.drawText(watermark, {
    x: PAGE_WIDTH - PAGE_MARGIN - widthOf(font, watermark, WATERMARK_FONT),
    y: PAGE_MARGIN - 4,
    size: WATERMARK_FONT,
    font,
    color: colors.watermark,
    opacity: 0.65,
  });
}

function drawTags(
  page: PDFPage,
  tags: string[],
  x: number,
  y: number,
  font: PDFFont,
  colors: ColorPalette,
): void {
  if (tags.length === 0) {
    page.drawText("", { x, y, font, size: TAG_FONT });
    return;
  }
  let cursor = x;
  const maxX = x + CARD_WIDTH - CARD_PAD * 2;
  for (const tag of tags) {
    const label = ellipsize(tag, font, TAG_FONT, CARD_WIDTH - CARD_PAD * 2 - 16);
    const width = Math.min(widthOf(font, label, TAG_FONT) + 16, CARD_WIDTH - CARD_PAD * 2);
    if (cursor + width > maxX) break;
    drawPill(page, cursor, y, width, 19, colors.chip);
    page.drawText(label, { x: cursor + 8, y: y + 5.2, size: TAG_FONT, font, color: colors.chipText });
    cursor += width + 6;
  }
}

function drawFragment(
  page: PDFPage,
  fragment: CardFragment,
  x: number,
  top: number,
  font: PDFFont,
  fontBold: PDFFont,
  dateDisplay: "zh" | "iso",
  canRenderCjk: boolean,
  colors: ColorPalette,
): void {
  const y = top - fragment.height;
  drawRoundedRect(page, x + 3, y - 3, CARD_WIDTH, fragment.height, 12, colors.shadow);
  drawRoundedRect(page, x, y, CARD_WIDTH, fragment.height, 12, colors.card, {
    color: colors.border,
    width: 1,
  });
  drawRoundedRect(page, x, top - HEADER_HEIGHT, CARD_WIDTH, HEADER_HEIGHT, 12, colors.header);
  page.drawRectangle({ x, y: top - HEADER_HEIGHT, width: CARD_WIDTH, height: 12, color: colors.header });

  const continuation = fragment.continuation
    ? canRenderCjk ? "（续）" : " (cont.)"
    : "";
  const subject = ellipsize(
    `${fragment.assignment.subject}${continuation}`,
    fontBold,
    SUBJECT_FONT,
    CARD_WIDTH - CARD_PAD * 2,
  );
  page.drawText(subject, {
    x: x + CARD_PAD,
    y: top - 23,
    size: SUBJECT_FONT,
    font: fontBold,
    color: colors.headerText,
  });
  page.drawText(formatDate(fragment.assignment.date, dateDisplay), {
    x: x + CARD_PAD,
    y: top - 39,
    size: DATE_FONT,
    font,
    color: colors.dateText,
  });

  let lineY = top - HEADER_HEIGHT - 24;
  for (const line of fragment.lines) {
    page.drawText(line || " ", {
      x: x + CARD_PAD,
      y: lineY,
      size: CONTENT_FONT,
      font,
      color: colors.content,
    });
    lineY -= CONTENT_LINE_HEIGHT;
  }
  if (fragment.showTags) {
    drawTags(page, fragment.assignment.tags, x + CARD_PAD, y + 13, font, colors);
  } else {
    const continued = canRenderCjk ? "正文下页继续" : "Continued on next card";
    page.drawText(continued, {
      x: x + CARD_PAD,
      y: y + 15,
      size: TAG_FONT,
      font,
      color: colors.muted,
    });
  }
}

export function renderAssignmentDocument(
  pdfDoc: PDFDocument,
  document: UafDocument,
  font: PDFFont,
  fontBold: PDFFont,
  options: {
    dateDisplay?: "zh" | "iso";
    canRenderCjk?: boolean;
    theme?: UafPdfTheme;
  } = {},
): PDFPage[] {
  const fragments = createFragments(document, font);
  const pages: PDFPage[] = [];
  const dateDisplay = options.dateDisplay ?? "zh";
  const colors = options.theme === "classworks-dark" ? CLASSWORKS_DARK_COLORS : DEFAULT_COLORS;
  const pageBottom = PAGE_MARGIN + WATERMARK_SPACE;
  let page: PDFPage | undefined;
  let cursorTop = PAGE_HEIGHT - PAGE_MARGIN;

  for (let index = 0; index < fragments.length; index += 2) {
    const pair = fragments.slice(index, index + 2);
    const rowHeight = Math.max(...pair.map((fragment) => fragment.height));
    if (!page || cursorTop - rowHeight < pageBottom) {
      page = pdfDoc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
      pages.push(page);
      drawPageBackground(page, font, options.canRenderCjk !== false, colors);
      cursorTop = PAGE_HEIGHT - PAGE_MARGIN;
    }
    pair.forEach((fragment, column) => {
      drawFragment(
        page!,
        fragment,
        PAGE_MARGIN + column * (CARD_WIDTH + COLUMN_GAP),
        cursorTop,
        font,
        fontBold,
        dateDisplay,
        options.canRenderCjk !== false,
        colors,
      );
    });
    cursorTop -= rowHeight + ROW_GAP;
  }
  return pages;
}
