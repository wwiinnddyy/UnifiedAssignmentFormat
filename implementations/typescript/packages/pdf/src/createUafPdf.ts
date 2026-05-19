import fontkit from "@pdf-lib/fontkit";
import { AFRelationship, PDFDocument, StandardFonts } from "pdf-lib";
import {
  parsePayload,
  serializePayload,
  UAF_PAYLOAD_FILENAME,
  validatePayload,
  type UafPayload,
} from "@uaf/core";
import { collectPdfText, loadChineseFontForText } from "./font.js";
import { renderAssignmentCard } from "./renderCard.js";

export interface CreateUafPdfOptions {
  fontBytes?: Uint8Array;
  /** Fast path for tests: skip embedding large CJK font (CSV round-trip unchanged). */
  useStandardFont?: boolean;
}

export async function createUafPdf(
  payload: UafPayload,
  options: CreateUafPdfOptions = {},
): Promise<Uint8Array> {
  const validated = validatePayload(payload);
  const csv = serializePayload(validated);
  const csvBytes = new TextEncoder().encode(csv);

  const pdfDoc = await PDFDocument.create();

  const dateDisplay = options.useStandardFont ? "iso" : "zh";

  let font;
  let fontBold;
  if (options.useStandardFont) {
    font = await pdfDoc.embedFont(StandardFonts.Helvetica);
    fontBold = font;
  } else {
    pdfDoc.registerFontkit(fontkit);
    const fontBytes =
      options.fontBytes ??
      (await loadChineseFontForText(collectPdfText(validated, dateDisplay)));
    font = await pdfDoc.embedFont(fontBytes, { subset: true });
    fontBold = font;
  }

  const page = pdfDoc.addPage([595.28, 841.89]);
  renderAssignmentCard(page, validated, font, fontBold, {
    dateDisplay,
  });

  await pdfDoc.attach(csvBytes, UAF_PAYLOAD_FILENAME, {
    mimeType: "text/csv",
    description: "UAF v1.0 payload",
    afRelationship: AFRelationship.Data,
    creationDate: new Date(),
    modificationDate: new Date(),
  });

  return pdfDoc.save();
}

export async function createUafPdfFromCsv(
  csv: string,
  options: CreateUafPdfOptions = {},
): Promise<Uint8Array> {
  const payload = parsePayload(csv);
  return createUafPdf(payload, options);
}
