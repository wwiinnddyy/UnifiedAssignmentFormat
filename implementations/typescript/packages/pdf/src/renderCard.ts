import type { PDFPage, PDFFont } from "pdf-lib";
import { rgb } from "pdf-lib";
import type { UafPayload } from "@uaf/core";
import { drawPill, drawRoundedRect } from "./drawShapes.js";

export const PAGE_WIDTH = 595.28;
export const PAGE_HEIGHT = 841.89;

const MARGIN = 40;
const CARD_RADIUS = 16;
const INNER_PAD = 24;
const SECTION_GAP = 20;
const TAG_ROW_GAP = 8;
const TAG_LINE_STEP = 28;

const COLORS = {
  pageBg: rgb(248 / 255, 250 / 255, 252 / 255),
  cardBg: rgb(1, 1, 1),
  shadow: rgb(226 / 255, 232 / 255, 240 / 255),
  subjectBg: rgb(37 / 255, 99 / 255, 235 / 255),
  subjectText: rgb(1, 1, 1),
  dateBg: rgb(241 / 255, 245 / 255, 249 / 255),
  dateText: rgb(51 / 255, 65 / 255, 85 / 255),
  content: rgb(15 / 255, 23 / 255, 42 / 255),
  tagBg: rgb(224 / 255, 231 / 255, 255 / 255),
  tagText: rgb(55 / 255, 48 / 255, 163 / 255),
  border: rgb(226 / 255, 232 / 255, 240 / 255),
};

const FONT_SIZES = [22, 18, 16, 14];

const SUBJECT_FONT = 14;
const SUBJECT_PAD_X = 16;
const SUBJECT_PAD_Y = 8;
const DATE_FONT = 12;
const DATE_PAD_X = 12;
const DATE_PAD_Y = 6;
const TAG_FONT = 11;
const TAG_PAD_X = 10;
const TAG_PAD_Y = 5;

function formatDateDisplay(isoDate: string): string {
  const d = new Date(isoDate);
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
}

function wrapText(text: string, font: PDFFont, fontSize: number, maxWidth: number): string[] {
  const lines: string[] = [];
  let current = "";

  for (const char of text) {
    if (char === "\n") {
      if (current) lines.push(current);
      current = "";
      continue;
    }
    const test = current + char;
    if (font.widthOfTextAtSize(test, fontSize) > maxWidth && current.length > 0) {
      lines.push(current);
      current = char;
    } else {
      current = test;
    }
  }
  if (current) lines.push(current);
  return lines.length > 0 ? lines : [""];
}

interface TagChip {
  label: string;
  w: number;
  h: number;
}

function layoutTags(tags: string[], font: PDFFont, maxWidth: number): { chips: TagChip[]; height: number } {
  if (tags.length === 0) return { chips: [], height: 0 };

  const chipH = TAG_FONT + TAG_PAD_Y * 2;
  const chips: TagChip[] = [];
  let x = 0;
  let row = 0;
  const maxRows = 2;

  for (const label of tags) {
    const w = font.widthOfTextAtSize(label, TAG_FONT) + TAG_PAD_X * 2;
    if (x + w > maxWidth && x > 0) {
      row++;
      x = 0;
    }
    if (row >= maxRows) break;
    chips.push({ label, w, h: chipH });
    x += w + TAG_ROW_GAP;
  }

  const rows = row + 1;
  return { chips, height: rows * TAG_LINE_STEP };
}

interface CardLayout {
  cardX: number;
  cardW: number;
  cardTop: number;
  cardHeight: number;
  contentLines: string[];
  contentFontSize: number;
  lineHeight: number;
  tagChips: TagChip[];
  tagBlockHeight: number;
  headerH: number;
  dateLabel: string;
}

function layoutCard(payload: UafPayload, font: PDFFont, dateLabel: string): CardLayout {
  const cardX = MARGIN;
  const cardW = PAGE_WIDTH - MARGIN * 2;
  const contentWidth = cardW - INNER_PAD * 2;

  const subjectH = SUBJECT_FONT + SUBJECT_PAD_Y * 2;
  const dateH = DATE_FONT + DATE_PAD_Y * 2;
  const headerH = Math.max(subjectH, dateH);

  const maxContentHeight =
    PAGE_HEIGHT - MARGIN * 2 - INNER_PAD * 2 - headerH - SECTION_GAP * 2 - TAG_LINE_STEP * 2 - 40;

  let contentFontSize = FONT_SIZES[0];
  let contentLines: string[] = [];

  for (const size of FONT_SIZES) {
    contentFontSize = size;
    contentLines = wrapText(payload.content, font, size, contentWidth);
    const h = contentLines.length * size * 1.5;
    if (h <= maxContentHeight) break;
  }

  const lineHeight = contentFontSize * 1.5;
  let maxLines = Math.max(1, Math.floor(maxContentHeight / lineHeight));
  if (contentLines.length > maxLines) {
    contentLines = contentLines.slice(0, maxLines);
    const last = contentLines[contentLines.length - 1];
    contentLines[contentLines.length - 1] = last.length > 1 ? `${last.slice(0, -1)}…` : "…";
  }

  const contentHeight = contentLines.length * lineHeight;
  const { chips: tagChips, height: tagBlockHeight } = layoutTags(
    payload.tags,
    font,
    contentWidth,
  );

  const tagSection = tagBlockHeight > 0 ? tagBlockHeight + SECTION_GAP : 0;
  const cardHeight =
    INNER_PAD + headerH + SECTION_GAP + contentHeight + tagSection + INNER_PAD;

  const cardTop = PAGE_HEIGHT - MARGIN;

  return {
    cardX,
    cardW,
    cardTop,
    cardHeight,
    contentLines,
    contentFontSize,
    lineHeight,
    tagChips,
    tagBlockHeight,
    headerH,
    dateLabel,
  };
}

export function renderAssignmentCard(
  page: PDFPage,
  payload: UafPayload,
  font: PDFFont,
  fontBold: PDFFont,
  options: { dateDisplay?: "zh" | "iso" } = {},
): void {
  const dateLabel =
    options.dateDisplay === "iso" ? payload.date : formatDateDisplay(payload.date);

  page.drawRectangle({
    x: 0,
    y: 0,
    width: PAGE_WIDTH,
    height: PAGE_HEIGHT,
    color: COLORS.pageBg,
  });

  const layout = layoutCard(payload, font, dateLabel);
  const cardBottom = layout.cardTop - layout.cardHeight;

  drawRoundedRect(
    page,
    layout.cardX + 2,
    cardBottom - 2,
    layout.cardW,
    layout.cardHeight,
    CARD_RADIUS,
    COLORS.shadow,
  );

  drawRoundedRect(
    page,
    layout.cardX,
    cardBottom,
    layout.cardW,
    layout.cardHeight,
    CARD_RADIUS,
    COLORS.cardBg,
    { color: COLORS.border, width: 1 },
  );

  const innerLeft = layout.cardX + INNER_PAD;
  const innerRight = layout.cardX + layout.cardW - INNER_PAD;
  let cursorY = layout.cardTop - INNER_PAD;

  const subjectLabel = payload.subject;
  const subjectTextW = fontBold.widthOfTextAtSize(subjectLabel, SUBJECT_FONT);
  const subjectW = subjectTextW + SUBJECT_PAD_X * 2;
  const subjectH = SUBJECT_FONT + SUBJECT_PAD_Y * 2;
  const subjectY = cursorY - subjectH;

  drawPill(page, innerLeft, subjectY, subjectW, subjectH, COLORS.subjectBg);
  page.drawText(subjectLabel, {
    x: innerLeft + SUBJECT_PAD_X,
    y: subjectY + SUBJECT_PAD_Y,
    size: SUBJECT_FONT,
    font: fontBold,
    color: COLORS.subjectText,
  });

  const dateTextW = font.widthOfTextAtSize(dateLabel, DATE_FONT);
  const dateW = dateTextW + DATE_PAD_X * 2;
  const dateH = DATE_FONT + DATE_PAD_Y * 2;
  const dateX = innerRight - dateW;
  const dateY = subjectY + (subjectH - dateH) / 2;

  drawPill(page, dateX, dateY, dateW, dateH, COLORS.dateBg);
  page.drawText(dateLabel, {
    x: dateX + DATE_PAD_X,
    y: dateY + DATE_PAD_Y,
    size: DATE_FONT,
    font,
    color: COLORS.dateText,
  });

  cursorY = subjectY - SECTION_GAP;

  let textY = cursorY;
  for (const line of layout.contentLines) {
    textY -= layout.contentFontSize;
    page.drawText(line, {
      x: innerLeft,
      y: textY,
      size: layout.contentFontSize,
      font,
      color: COLORS.content,
    });
    textY -= layout.lineHeight - layout.contentFontSize;
  }

  if (layout.tagChips.length > 0) {
    let tagX = innerLeft;
    let tagY = textY - SECTION_GAP - layout.tagChips[0].h;
    let row = 0;

    for (const chip of layout.tagChips) {
      if (tagX + chip.w > innerRight && tagX > innerLeft) {
        row++;
        if (row >= 2) break;
        tagX = innerLeft;
        tagY -= TAG_LINE_STEP;
      }

      drawPill(page, tagX, tagY, chip.w, chip.h, COLORS.tagBg);
      page.drawText(chip.label, {
        x: tagX + TAG_PAD_X,
        y: tagY + TAG_PAD_Y,
        size: TAG_FONT,
        font,
        color: COLORS.tagText,
      });

      tagX += chip.w + TAG_ROW_GAP;
    }
  }
}
