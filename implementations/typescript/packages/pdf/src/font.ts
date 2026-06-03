import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { UafPayload } from "@uaf/core";

const packageDir = dirname(fileURLToPath(import.meta.url));

let coreFontBytes: Uint8Array | undefined;

/** Characters used when rendering a homework card (for font subsetting). */
export function collectPdfText(payload: UafPayload, dateDisplay: "zh" | "iso" = "zh"): string {
  const parts = [payload.subject, payload.content, ...payload.tags];
  if (dateDisplay === "zh") {
    const d = new Date(payload.date);
    parts.push(`${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`);
    parts.push("年月日");
  } else {
    parts.push(payload.date);
  }
  return [...new Set(parts.join(""))].sort().join("");
}

async function loadCoreFontBytes(): Promise<Uint8Array> {
  if (coreFontBytes) return coreFontBytes;

  const corePath = join(packageDir, "..", "assets", "NotoSansSC-Core.woff2");
  try {
    coreFontBytes = new Uint8Array(await readFile(corePath));
    return coreFontBytes;
  } catch {
    throw new Error(
      "Chinese font not found. Run: node packages/pdf/scripts/build-core-font.mjs and commit packages/pdf/assets/NotoSansSC-Core.woff2.",
    );
  }
}

/**
 * Returns the committed core woff2 (~40KB). pdf-lib embeds the full font directly.
 * `text` is reserved for future per-payload core builds.
 */
export async function loadChineseFontForText(_text: string): Promise<Uint8Array> {
  return loadCoreFontBytes();
}

/** @deprecated Use loadChineseFontForText with collectPdfText. */
export async function loadChineseFont(): Promise<Uint8Array> {
  return loadCoreFontBytes();
}

export function getFontPath(): string {
  return join(packageDir, "..", "assets", "NotoSansSC-Core.woff2");
}
