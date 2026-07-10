import { copyFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(resolve(here, "..", "package.json"));
const source = require.resolve("harfbuzzjs/hb-subset.wasm");
await copyFile(source, resolve(here, "..", "assets", "hb-subset.wasm"));
console.log("Synced hb-subset.wasm into @uaf/pdf assets.");
