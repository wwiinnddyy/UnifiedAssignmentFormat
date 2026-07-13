import { PDFDocument, StandardFonts, rgb } from "pdf-lib";
import { writeFile } from "node:fs/promises";

const pdfDoc = await PDFDocument.create();
const page = pdfDoc.addPage([595.28, 841.89]);
const font = await pdfDoc.embedFont(StandardFonts.Helvetica);

const bg = rgb(20 / 255, 18 / 255, 24 / 255);
const watermarkColor = rgb(188 / 255, 184 / 255, 188 / 255);
const text = "Exported with UAF v1.0";
const size = 9;
const width = font.widthOfTextAtSize(text, size);

page.drawRectangle({ x: 0, y: 0, width: 595.28, height: 841.89, color: bg });
page.drawText(text, {
  x: 595.28 - 40 - width,
  y: 40 - 4,
  size,
  font,
  color: watermarkColor,
});

page.drawText("fixed color watermark", { x: 40, y: 800, size: 12, font, color: rgb(1, 1, 1) });

await writeFile("test-watermark.pdf", await pdfDoc.save());
console.log("Generated test-watermark.pdf");
