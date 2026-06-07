import type { UafPayload } from "@uaf/core";
import { extractUafPayloadFromHtml } from "./extractUafHtml.js";

export interface UafHtmlValidationResult {
  valid: boolean;
  payload?: UafPayload;
  errors: string[];
}

export function validateUafHtml(html: string): UafHtmlValidationResult {
  const errors: string[] = [];
  let payload: UafPayload | undefined;

  try {
    payload = extractUafPayloadFromHtml(html);
  } catch (e) {
    errors.push(e instanceof Error ? e.message : "Unknown HTML validation error");
  }

  errors.push(...validatePrintableStructure(html));

  if (errors.length > 0) {
    return {
      valid: false,
      errors,
    };
  }

  return {
    valid: true,
    payload,
    errors: [],
  };
}

function validatePrintableStructure(html: string): string[] {
  const errors: string[] = [];

  if (!/^\s*<!DOCTYPE html>/i.test(html)) {
    errors.push("HTML must start with an HTML5 doctype");
  }
  if (!/<style\b[\s\S]*?<\/style>/i.test(html)) {
    errors.push("HTML must inline its print CSS in a style tag");
  }
  if (!/@page\b/i.test(html)) {
    errors.push("HTML must define @page print CSS");
  }
  if (!/size\s*:\s*A4\s+portrait/i.test(html)) {
    errors.push("HTML print CSS must set size: A4 portrait");
  }
  if (!/print-color-adjust\s*:\s*exact/i.test(html)) {
    errors.push("HTML print CSS must preserve background colors when printed");
  }
  if (!/border-radius\s*:\s*16pt/i.test(html)) {
    errors.push("HTML must preserve the UAF rounded card styling");
  }
  if (
    !/<template\b(?=[^>]*\bid=(["'])uaf-payload-csv\1)(?=[^>]*\bdata-filename=(["'])uaf_payload\.csv\2)[^>]*>/i.test(
      html,
    )
  ) {
    errors.push('HTML payload template must declare data-filename="uaf_payload.csv"');
  }
  if (/<link\b|<script\b|\bsrc\s*=/i.test(html)) {
    errors.push("HTML must stay self-contained without external assets or scripts");
  }

  return errors;
}
