import type { PDFPage, PDFFont } from "pdf-lib";
import { rgb } from "pdf-lib";
import type { UafPayload } from "@uaf/core";

const PAGE_WIDTH = 595.28;
const PAGE_HEIGHT = 841.89;
const MARGIN = 48;

const COLORS = {
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
    const width = font.widthOfTextAtSize(test, fontSize);
    if (width > maxWidth && current.length > 0) {
      lines.push(current);
      current = char;
    } else {
      current = test;
    }
  }

  if (current) lines.push(current);
  return lines.length > 0 ? lines : [""];
}

function measureContentHeight(lines: string[], lineHeight: number): number {
  return lines.length * lineHeight;
}

function drawChip(
  page: PDFPage,
  x: number,
  y: number,
  w: number,
  h: number,
  color: ReturnType<typeof rgb>,
): void {
  page.drawRectangle({ x, y, width: w, height: h, color });
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
  const contentWidth = PAGE_WIDTH - MARGIN * 2;
  const borderInset = 36;
  const cardX = borderInset;
  const cardY = borderInset;
  const cardW = PAGE_WIDTH - borderInset * 2;
  const cardH = PAGE_HEIGHT - borderInset * 2;

  page.drawRectangle({
    x: cardX,
    y: cardY,
    width: cardW,
    height: cardH,
    borderColor: COLORS.border,
    borderWidth: 1,
  });

  const subjectLabel = payload.subject;
  const subjectFontSize = 14;
  const subjectPadX = 16;
  const subjectPadY = 8;
  const subjectTextW = fontBold.widthOfTextAtSize(subjectLabel, subjectFontSize);
  const subjectW = subjectTextW + subjectPadX * 2;
  const subjectH = subjectFontSize + subjectPadY * 2;
  const topY = PAGE_HEIGHT - MARGIN - subjectH;

  drawChip(page, MARGIN, topY, subjectW, subjectH, COLORS.subjectBg);
  page.drawText(subjectLabel, {
    x: MARGIN + subjectPadX,
    y: topY + subjectPadY,
    size: subjectFontSize,
    font: fontBold,
    color: COLORS.subjectText,
  });

  const dateFontSize = 12;
  const datePadX = 12;
  const datePadY = 6;
  const dateTextW = font.widthOfTextAtSize(dateLabel, dateFontSize);
  const dateW = dateTextW + datePadX * 2;
  const dateH = dateFontSize + datePadY * 2;
  const dateX = PAGE_WIDTH - MARGIN - dateW;
  const dateY = topY + (subjectH - dateH) / 2;

  drawChip(page, dateX, dateY, dateW, dateH, COLORS.dateBg);
  page.drawText(dateLabel, {
    x: dateX + datePadX,
    y: dateY + datePadY,
    size: dateFontSize,
    font,
    color: COLORS.dateText,
  });

  const contentTop = topY - 40;
  const contentBottom = 180;
  const maxContentHeight = contentTop - contentBottom;

  let chosenSize = FONT_SIZES[0];
  let lines: string[] = [];

  for (const fontSize of FONT_SIZES) {
    const lineHeight = fontSize * 1.5;
    lines = wrapText(payload.content, font, fontSize, contentWidth);
    const h = measureContentHeight(lines, lineHeight);
    if (h <= maxContentHeight) {
      chosenSize = fontSize;
      break;
    }
    chosenSize = fontSize;
  }

  const lineHeight = chosenSize * 1.5;
  let maxLines = Math.floor(maxContentHeight / lineHeight);
  let truncated = false;
  if (lines.length > maxLines) {
    truncated = true;
    lines = lines.slice(0, maxLines);
    if (lines.length > 0) {
      const last = lines[lines.length - 1];
      lines[lines.length - 1] = last.length > 1 ? `${last.slice(0, -1)}…` : "…";
    }
  }

  let textY = contentTop;
  for (const line of lines) {
    page.drawText(line, {
      x: MARGIN,
      y: textY - chosenSize,
      size: chosenSize,
      font,
      color: COLORS.content,
    });
    textY -= lineHeight;
  }

  if (truncated) {
    // visual spec: truncate with ellipsis at smallest size
  }

  let tagX = MARGIN;
  let tagY = 120;
  const tagLineHeight = 28;
  let tagLine = 0;
  const maxTagLines = 2;

  for (const tag of payload.tags) {
    const tagFontSize = 11;
    const tagPadX = 10;
    const tagPadY = 5;
    const tagTextW = font.widthOfTextAtSize(tag, tagFontSize);
    const chipW = tagTextW + tagPadX * 2;
    const chipH = tagFontSize + tagPadY * 2;

    if (tagX + chipW > PAGE_WIDTH - MARGIN) {
      tagLine++;
      tagX = MARGIN;
      tagY -= tagLineHeight;
    }

    if (tagLine >= maxTagLines) break;

    drawChip(page, tagX, tagY, chipW, chipH, COLORS.tagBg);
    page.drawText(tag, {
      x: tagX + tagPadX,
      y: tagY + tagPadY,
      size: tagFontSize,
      font,
      color: COLORS.tagText,
    });

    tagX += chipW + 8;
  }
}

export { PAGE_WIDTH, PAGE_HEIGHT };
