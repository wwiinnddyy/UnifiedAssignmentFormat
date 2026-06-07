import subsetFont from "subset-font";
import { readFile } from "fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const text = "数学完成课本第45页第1、2题，请拍照上传。必做几何重难点2026年5月19日";

const otf = await readFile(join(here, "../assets/NotoSansSC-Regular.otf"));
const out = await subsetFont(otf, text, { targetFormat: "sfnt" });
const header = Buffer.from(out).subarray(0, 4).toString("hex");

if (header !== "00010000") {
  throw new Error(`Expected SFNT/TrueType subset, got header ${header}`);
}

console.log("otf sfnt subset", otf.length, "->", out.length);
