import type { PDFPage, RGB } from "pdf-lib";

export interface ShapeBorder {
  color: RGB;
  width: number;
}

/** Build SVG path for a rounded rectangle (bottom-left origin, y up). */
function roundedRectPath(x: number, y: number, w: number, h: number, radius: number): string {
  const r = Math.min(radius, w / 2, h / 2);
  return [
    `M ${x + r} ${y}`,
    `L ${x + w - r} ${y}`,
    `Q ${x + w} ${y} ${x + w} ${y + r}`,
    `L ${x + w} ${y + h - r}`,
    `Q ${x + w} ${y + h} ${x + w - r} ${y + h}`,
    `L ${x + r} ${y + h}`,
    `Q ${x} ${y + h} ${x} ${y + h - r}`,
    `L ${x} ${y + r}`,
    `Q ${x} ${y} ${x + r} ${y}`,
    "Z",
  ].join(" ");
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
  const path = roundedRectPath(x, y, w, h, radius);
  page.drawSvgPath(path, {
    color: fill,
    borderColor: border?.color,
    borderWidth: border?.width ?? 0,
  });
}

/** Capsule / pill chip (height defines corner radius). */
export function drawPill(
  page: PDFPage,
  x: number,
  y: number,
  w: number,
  h: number,
  fill: RGB,
): void {
  drawRoundedRect(page, x, y, w, h, h / 2, fill);
}
