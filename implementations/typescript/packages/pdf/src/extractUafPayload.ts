import { parsePayload, type UafPayload } from "@uaf/core";
import { extractEmbeddedFile } from "./embeddedFiles.js";

export async function extractUafPayload(pdfBytes: Uint8Array): Promise<UafPayload> {
  const csvBytes = await extractEmbeddedFile(pdfBytes);
  const csv = new TextDecoder("utf-8").decode(csvBytes);
  return parsePayload(csv);
}

export async function extractUafPayloadCsv(pdfBytes: Uint8Array): Promise<string> {
  const csvBytes = await extractEmbeddedFile(pdfBytes);
  return new TextDecoder("utf-8").decode(csvBytes);
}
