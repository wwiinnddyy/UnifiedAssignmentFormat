import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const packageDir = dirname(fileURLToPath(import.meta.url));

/** Bundled OTF (run scripts/download-font.mjs once) or @fontsource fallback. */
export function getFontPath(): string {
  const bundled = join(packageDir, "..", "assets", "NotoSansSC-Regular.otf");
  return bundled;
}

let cachedFont: Uint8Array | undefined;

async function loadFromFontsource(): Promise<Uint8Array> {
  const pkgDir = dirname(require.resolve("@fontsource/noto-sans-sc/package.json"));
  const woff = join(pkgDir, "files", "noto-sans-sc-chinese-simplified-400-normal.woff");
  return new Uint8Array(await readFile(woff));
}

export async function loadChineseFont(): Promise<Uint8Array> {
  if (cachedFont) return cachedFont;

  const bundledPath = getFontPath();
  try {
    cachedFont = new Uint8Array(await readFile(bundledPath));
    return cachedFont;
  } catch {
    try {
      cachedFont = await loadFromFontsource();
      return cachedFont;
    } catch (cause) {
      throw new Error(
        `Chinese font not found. Place NotoSansSC-Regular.otf in packages/pdf/assets/ or install @fontsource/noto-sans-sc.`,
        { cause },
      );
    }
  }
}
