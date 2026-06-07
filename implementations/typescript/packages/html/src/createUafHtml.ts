import {
  parsePayload,
  validatePayload,
  type UafPayload,
} from "@uaf/core";
import { renderUafHtml, type RenderHtmlOptions } from "./renderHtml.js";

export interface CreateUafHtmlOptions extends RenderHtmlOptions {}

export function createUafHtml(
  payload: UafPayload,
  options: CreateUafHtmlOptions = {},
): string {
  return renderUafHtml(validatePayload(payload), options);
}

export function createUafHtmlFromCsv(
  csv: string,
  options: CreateUafHtmlOptions = {},
): string {
  return createUafHtml(parsePayload(csv), options);
}
