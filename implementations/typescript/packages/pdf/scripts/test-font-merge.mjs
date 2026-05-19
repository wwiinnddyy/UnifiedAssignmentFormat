import subsetFont from "subset-font";
import fonteditor from "fonteditor-core";
const { createFont, woff2 } = fonteditor;
import { readFile } from "fs/promises";
import { join, dirname } from "path";
import { createRequire } from "module";

const require = createRequire(import.meta.url);
const pkgDir = dirname(require.resolve("@fontsource/noto-sans-sc/package.json"));
const text = "数学完成课本第45页第1、2题，请拍照上传。必做几何重难点2026年5月19日";
const indices = [113, 115, 116, 117, 118, 119];

await woff2.init();

let merged = null;
for (const i of indices) {
  const buf = await readFile(join(pkgDir, "files", `noto-sans-sc-${i}-400-normal.woff2`));
  const subset = await subsetFont(buf, text, { targetFormat: "woff2" });
  const font = createFont(subset, { type: "woff2" });
  if (!merged) merged = font;
  else merged.merge(font);
}

const out = merged.write({ type: "woff2" });
console.log("merged woff2", out.length);
