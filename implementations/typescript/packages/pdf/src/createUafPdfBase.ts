import fontkit from "@pdf-lib/fontkit";
import { AFRelationship, PDFDocument, StandardFonts } from "pdf-lib";
import {
  serializePayload,
  UAF_PAYLOAD_FILENAME,
  validatePayload,
  type UafDocument,
} from "@uaf/core";
import { renderAssignmentDocument } from "./renderCard.js";

export interface CreateUafPdfBaseOptions {
  fontBytes?: Uint8Array;
  useStandardFont?: boolean;
  subsetFont?: boolean;
}

export async function createUafPdfWithFont(
  document: UafDocument,
  options: CreateUafPdfBaseOptions = {},
): Promise<Uint8Array> {
  const validated = validatePayload(document);
  const csvBytes = new TextEncoder().encode(serializePayload(validated));
  const pdfDoc = await PDFDocument.create();

  let font;
  if (options.useStandardFont) {
    font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  } else {
    if (!options.fontBytes) throw new Error("fontBytes are required for CJK PDF rendering");
    pdfDoc.registerFontkit(fontkit);
    font = await pdfDoc.embedFont(options.fontBytes, { subset: options.subsetFont ?? true });
  }

  renderAssignmentDocument(pdfDoc, validated, font, font, {
    dateDisplay: options.useStandardFont ? "iso" : "zh",
    canRenderCjk: !options.useStandardFont,
  });

  await pdfDoc.attach(csvBytes, UAF_PAYLOAD_FILENAME, {
    mimeType: "text/csv",
    description: "UAF v1.0 multi-assignment payload",
    afRelationship: AFRelationship.Data,
    creationDate: new Date(),
    modificationDate: new Date(),
  });
  return pdfDoc.save();
}
