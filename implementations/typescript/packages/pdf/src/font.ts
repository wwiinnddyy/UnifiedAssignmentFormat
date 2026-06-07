import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { UafPayload } from "@uaf/core";
import type subsetFont from "subset-font";

const packageDir = dirname(fileURLToPath(import.meta.url));

const FONT_SOURCE_NAME = "NotoSansSC-Regular.otf";

let sourceFontBytes: Uint8Array | undefined;
const subsetCache = new Map<string, Uint8Array>();

/** Characters used when rendering a homework card (for font subsetting). */
export function collectPdfText(payload: UafPayload, dateDisplay: "zh" | "iso" = "zh"): string {
  const parts = [payload.subject, payload.content, ...payload.tags, "使用 UAF 导出未标记..."];
  if (dateDisplay === "zh") {
    const d = new Date(payload.date);
    parts.push(`${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`);
    parts.push("年月日");
  } else {
    parts.push(payload.date);
  }
  return [...new Set(parts.join(""))].sort().join("");
}

async function loadSourceFontBytes(): Promise<Uint8Array> {
  if (sourceFontBytes) return sourceFontBytes;

  const sourcePath = join(packageDir, "..", "assets", FONT_SOURCE_NAME);
  try {
    sourceFontBytes = await readFile(sourcePath);
    return sourceFontBytes;
  } catch {
    throw new Error(
      `Chinese font not found. Expected packages/pdf/assets/${FONT_SOURCE_NAME}.`,
    );
  }
}

/**
 * Returns a PDF-renderable SFNT subset for the exact text being drawn.
 *
 * pdf-lib embeds non-CFF fonts as /FontFile2, which real PDF renderers expect
 * to contain SFNT/TrueType bytes. WOFF/WOFF2 can parse in fontkit but renders
 * as blank glyphs in PDF viewers once embedded this way.
 */
export async function loadChineseFontForText(text: string): Promise<Uint8Array> {
  const cacheKey = text || "UAF";
  const cached = subsetCache.get(cacheKey);
  if (cached) return cached;

  const source = await loadSourceFontBytes();
  const { default: createSubset } = (await import("subset-font")) as {
    default: typeof subsetFont;
  };
  const subset = new Uint8Array(
    await createSubset(source, cacheKey, { targetFormat: "sfnt" }),
  );
  subsetCache.set(cacheKey, subset);
  return subset;
}

/** @deprecated Use loadChineseFontForText with collectPdfText. */
export async function loadChineseFont(): Promise<Uint8Array> {
  return loadChineseFontForText("使用 UAF 导出");
}

export function getFontPath(): string {
  return join(packageDir, "..", "assets", FONT_SOURCE_NAME);
}
