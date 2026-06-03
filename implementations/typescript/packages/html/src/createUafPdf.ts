import { AFRelationship, PDFDocument } from "pdf-lib";
import {
  serializePayload,
  UAF_PAYLOAD_FILENAME,
  validatePayload,
  type UafPayload,
} from "@uaf/core";
import { renderUafHtml, type RenderHtmlOptions } from "./renderHtml.js";
import { htmlToPdf, type HtmlToPdfOptions } from "./htmlToPdf.js";

export interface CreateUafPdfFromHtmlOptions
  extends RenderHtmlOptions,
    HtmlToPdfOptions {}

/**
 * Create a UAF v1.0 compliant PDF using the HTML rendering pipeline.
 *
 * Steps:
 * 1. Validate the payload.
 * 2. Render the payload as a self-contained HTML document.
 * 3. Convert the HTML to PDF using Puppeteer (optional dependency).
 * 4. Embed the CSV payload as an attached file.
 *
 * Puppeteer must be installed for the PDF conversion step. If you only need
 * the HTML string, use {@link renderUafHtml} directly.
 */
export async function createUafPdfFromHtml(
  payload: UafPayload,
  options: CreateUafPdfFromHtmlOptions = {},
): Promise<Uint8Array> {
  const validated = validatePayload(payload);
  const csv = serializePayload(validated);
  const csvBytes = new TextEncoder().encode(csv);

  const html = renderUafHtml(validated, options);
  const pdfBytes = await htmlToPdf(html, options);

  const pdfDoc = await PDFDocument.load(pdfBytes);

  await pdfDoc.attach(csvBytes, UAF_PAYLOAD_FILENAME, {
    mimeType: "text/csv",
    description: "UAF v1.0 payload",
    afRelationship: AFRelationship.Data,
    creationDate: new Date(),
    modificationDate: new Date(),
  });

  return pdfDoc.save();
}