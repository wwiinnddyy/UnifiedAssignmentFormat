import { parsePayload, type UafDocument } from "@uaf/core";
import { createUafPdfWithFont } from "./createUafPdfBase.js";
import { collectDocumentText, subsetFontInBrowser } from "./browserSubset.js";

export interface CreateUafPdfBrowserOptions {
  fontBytes?: Uint8Array;
  fontUrl?: string | URL;
  wasmUrl?: string | URL;
}

let cachedFontBytes: Uint8Array | undefined;

async function loadBrowserFont(options: CreateUafPdfBrowserOptions): Promise<Uint8Array> {
  if (options.fontBytes) return options.fontBytes;
  if (cachedFontBytes) return cachedFontBytes;
  const url = options.fontUrl ?? new URL("../assets/NotoSansSC-Regular.otf", import.meta.url);
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Failed to load UAF font: ${response.status}`);
  cachedFontBytes = new Uint8Array(await response.arrayBuffer());
  return cachedFontBytes;
}

export async function createUafPdf(
  document: UafDocument,
  options: CreateUafPdfBrowserOptions = {},
): Promise<Uint8Array> {
  const fontBytes = await loadBrowserFont(options);
  const wasmUrl = options.wasmUrl ?? new URL("../assets/hb-subset.wasm", import.meta.url);
  const subset = await subsetFontInBrowser(fontBytes, collectDocumentText(document), wasmUrl);
  return createUafPdfWithFont(document, { fontBytes: subset, subsetFont: false });
}

export async function createUafPdfFromCsv(
  csv: string,
  options: CreateUafPdfBrowserOptions = {},
): Promise<Uint8Array> {
  return createUafPdf(parsePayload(csv), options);
}

export { extractUafPayload, extractUafPayloadCsv } from "./extractUafPayload.js";
export { validateUafPdf } from "./validateUafPdf.js";
