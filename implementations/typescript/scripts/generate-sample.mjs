import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..", "..", "..");

async function main() {
  const { createUafPdf, loadChineseFont } = await import("../packages/pdf/dist/index.js");
  const { serializePayload } = await import("../packages/core/dist/index.js");

  const payload = {
    subject: "数学",
    date: "2026-05-19",
    content: "完成课本第45页第1、2题，请拍照上传。",
    tags: ["必做", "几何", "重难点"],
  };

  const csv = serializePayload(payload);
  const examplesDir = join(repoRoot, "examples");
  await mkdir(examplesDir, { recursive: true });
  await writeFile(join(examplesDir, "uaf_payload.sample.csv"), csv, "utf-8");

  await loadChineseFont();
  const pdfBytes = await createUafPdf(payload);
  await writeFile(join(examplesDir, "sample-homework.pdf"), pdfBytes);
  console.log(`Generated ${examplesDir}/uaf_payload.sample.csv and sample-homework.pdf`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
