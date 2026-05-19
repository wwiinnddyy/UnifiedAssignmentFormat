/**
 * Legacy script — fonts are now provided via @fontsource/noto-sans-sc (pnpm install).
 * Kept for backward compatibility; copies font to packages/pdf/assets for optional offline use.
 */
import { copyFile, mkdir } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const __dirname = dirname(fileURLToPath(import.meta.url));
const outDir = join(__dirname, "..", "packages", "pdf", "assets");

async function main() {
  const pkgDir = dirname(require.resolve("@fontsource/noto-sans-sc/package.json"));
  const src = join(pkgDir, "files", "noto-sans-sc-chinese-simplified-400-normal.woff");
  await mkdir(outDir, { recursive: true });
  const dest = join(outDir, "NotoSansSC-Regular.woff");
  await copyFile(src, dest);
  console.log(`Copied font to ${dest}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
