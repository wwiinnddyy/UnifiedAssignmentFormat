import { PDFDocument } from "pdf-lib";
import { UafError } from "@uaf/core";
import { extractUafPayload } from "./extractUafPayload.js";

export interface UafValidationResult {
  valid: boolean;
  pageCount: number;
  payload?: Awaited<ReturnType<typeof extractUafPayload>>;
  errors: string[];
}

export async function validateUafPdf(pdfBytes: Uint8Array): Promise<UafValidationResult> {
  const errors: string[] = [];

  let pdfDoc: PDFDocument;
  try {
    pdfDoc = await PDFDocument.load(pdfBytes, { ignoreEncryption: true });
  } catch {
    return {
      valid: false,
      pageCount: 0,
      errors: ["Failed to load PDF"],
    };
  }

  const pageCount = pdfDoc.getPageCount();
  if (pageCount !== 1) {
    errors.push(`Expected 1 page, got ${pageCount}`);
  }

  try {
    const payload = await extractUafPayload(pdfBytes);
    return {
      valid: errors.length === 0,
      pageCount,
      payload,
      errors,
    };
  } catch (e) {
    if (e instanceof UafError) {
      errors.push(e.message);
      return {
        valid: false,
        pageCount,
        errors,
      };
    }
    errors.push(e instanceof Error ? e.message : "Unknown error");
    return {
      valid: false,
      pageCount,
      errors,
    };
  }
}
