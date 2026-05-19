import subsetFont from "subset-font";
import { readFile } from "fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "module";

const require = createRequire(import.meta.url);
const pkgDir = dirname(require.resolve("@fontsource/noto-sans-sc/package.json"));
const here = dirname(fileURLToPath(import.meta.url));
const text = "数学完成课本第45页第1、2题，请拍照上传。必做几何重难点2026年5月19日";

const otf = await readFile(join(here, "../assets/NotoSansSC-Regular.otf"));
const out = await subsetFont(otf, text, { targetFormat: "woff2" });
console.log("otf subset", otf.length, "->", out.length);
