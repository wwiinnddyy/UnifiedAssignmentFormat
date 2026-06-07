import {
  parsePayload,
  UafError,
  UafErrorCode,
  type UafPayload,
} from "@uaf/core";

const PAYLOAD_TEMPLATE_RE =
  /<template\b(?=[^>]*\bid=(["'])uaf-payload-csv\1)[^>]*>([\s\S]*?)<\/template>/i;

export function extractUafPayloadCsvFromHtml(html: string): string {
  const match = PAYLOAD_TEMPLATE_RE.exec(html);
  if (!match) {
    throw new UafError(
      UafErrorCode.NoPayload,
      "HTML does not contain a uaf-payload-csv template",
    );
  }

  return decodeHtmlEntities(match[2]);
}

export function extractUafPayloadFromHtml(html: string): UafPayload {
  return parsePayload(extractUafPayloadCsvFromHtml(html));
}

function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&gt;/g, ">")
    .replace(/&lt;/g, "<")
    .replace(/&amp;/g, "&");
}
