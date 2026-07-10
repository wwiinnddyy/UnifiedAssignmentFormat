import { parsePayload, type UafDocument } from "@uaf/core";
import { collectPdfText, loadChineseFontForText } from "./font.js";
import { createUafPdfWithFont, type CreateUafPdfBaseOptions } from "./createUafPdfBase.js";

export type CreateUafPdfOptions = CreateUafPdfBaseOptions;

export async function createUafPdf(
  document: UafDocument,
  options: CreateUafPdfOptions = {},
): Promise<Uint8Array> {
  if (options.useStandardFont) return createUafPdfWithFont(document, options);
  const fontBytes = options.fontBytes ?? (await loadChineseFontForText(collectPdfText(document)));
  return createUafPdfWithFont(document, { ...options, fontBytes, subsetFont: false });
}

export async function createUafPdfFromCsv(
  csv: string,
  options: CreateUafPdfOptions = {},
): Promise<Uint8Array> {
  return createUafPdf(parsePayload(csv), options);
}
