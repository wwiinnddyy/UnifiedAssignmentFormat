import type { PDFPage, RGB } from "pdf-lib";

export interface ShapeBorder {
  color: RGB;
  width: number;
}

function drawFilledRoundedRect(
  page: PDFPage,
  x: number,
  y: number,
  w: number,
  h: number,
  radius: number,
  fill: RGB,
): void {
  const r = Math.max(0, Math.min(radius, w / 2, h / 2));

  page.drawRectangle({
    x: x + r,
    y,
    width: Math.max(0, w - r * 2),
    height: h,
    color: fill,
  });
  page.drawRectangle({
    x,
    y: y + r,
    width: w,
    height: Math.max(0, h - r * 2),
    color: fill,
  });
  page.drawCircle({ x: x + r, y: y + r, size: r, color: fill });
  page.drawCircle({ x: x + w - r, y: y + r, size: r, color: fill });
  page.drawCircle({ x: x + r, y: y + h - r, size: r, color: fill });
  page.drawCircle({ x: x + w - r, y: y + h - r, size: r, color: fill });
}

export function drawRoundedRect(
  page: PDFPage,
  x: number,
  y: number,
  w: number,
  h: number,
  radius: number,
  fill: RGB,
  border?: ShapeBorder,
): void {
  if (border && border.width > 0) {
    drawFilledRoundedRect(page, x, y, w, h, radius, border.color);

    const inset = border.width;
    drawFilledRoundedRect(
      page,
      x + inset,
      y + inset,
      Math.max(0, w - inset * 2),
      Math.max(0, h - inset * 2),
      Math.max(0, radius - inset),
      fill,
    );
    return;
  }

  drawFilledRoundedRect(page, x, y, w, h, radius, fill);
}

/** Capsule / pill chip (height defines corner radius). */
export function drawPill(
  page: PDFPage,
  x: number,
  y: number,
  w: number,
  h: number,
  fill: RGB,
  border?: ShapeBorder,
): void {
  drawRoundedRect(page, x, y, w, h, h / 2, fill, border);
}
