/**
 * Builds packages/pdf/assets/NotoSansSC-Core.woff2 (committed, ~20–80KB).
 * Requires local NotoSansSC-Regular.otf OR @fontsource/noto-sans-sc slices.
 */
import subsetFont from "subset-font";
import { readFile, writeFile, mkdir } from "fs/promises";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { createRequire } from "module";

const require = createRequire(import.meta.url);
const here = dirname(fileURLToPath(import.meta.url));
const assetsDir = join(here, "../assets");
const outPath = join(assetsDir, "NotoSansSC-Core.woff2");

const SAMPLE =
  "数学完成课本第45页第1、2题，请拍照上传。必做几何重难点语文英语物理化学生物历史地理政治音乐美术体育信息技术科学实验阅读写作背诵默写订正家长签字";
const CORE_EXTRA =
  '0123456789年月日，。、；：？！""\'\'（）【】《》…—·!?.,;:\'"-/\\';

const text = [...new Set((SAMPLE + CORE_EXTRA).split(""))].join("");

function parseRanges(s) {
  return s
    .split(",")
    .map((part) => {
      part = part.trim();
      if (!part.startsWith("U+")) return null;
      if (part.includes("-")) {
        const [a, b] = part.slice(2).split("-").map((x) => parseInt(x, 16));
        return [a, b];
      }
      const cp = parseInt(part.slice(2), 16);
      return [cp, cp];
    })
    .filter(Boolean);
}

async function subsetFromFontsource() {
  const pkgDir = dirname(require.resolve("@fontsource/noto-sans-sc/package.json"));
  const unicode = JSON.parse(await readFile(join(pkgDir, "unicode.json"), "utf8"));
  const ranges = {};
  for (const [k, v] of Object.entries(unicode)) {
    ranges[parseInt(k.slice(1, -1), 10)] = parseRanges(v);
  }

  function findIndex(cp) {
    for (const [idx, rs] of Object.entries(ranges)) {
      for (const [a, b] of rs) {
        if (cp >= a && cp <= b) return Number(idx);
      }
    }
    return null;
  }

  const indices = new Set();
  for (const ch of text) {
    const i = findIndex(ch.codePointAt(0));
    if (i != null) indices.add(i);
  }

  const parts = [];
  for (const i of [...indices].sort((a, b) => a - b)) {
    const path = join(pkgDir, "files", `noto-sans-sc-${i}-400-normal.woff2`);
    const buf = await readFile(path);
    parts.push(await subsetFont(buf, text, { targetFormat: "woff2" }));
  }

  if (parts.length === 1) return parts[0];
  throw new Error(
    `Text spans ${parts.length} fontsource slices; place NotoSansSC-Regular.otf in assets/ and re-run, or merge slices manually.`,
  );
}

async function main() {
  await mkdir(assetsDir, { recursive: true });

  let merged;
  const otfPath = join(assetsDir, "NotoSansSC-Regular.otf");
  try {
    const otf = await readFile(otfPath);
    merged = await subsetFont(otf, text, { targetFormat: "woff2" });
    console.log("Built from OTF");
  } catch {
    merged = await subsetFromFontsource();
    console.log("Built from fontsource");
  }

  await writeFile(outPath, merged);
  console.log(`Wrote ${outPath} (${merged.length} bytes)`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
