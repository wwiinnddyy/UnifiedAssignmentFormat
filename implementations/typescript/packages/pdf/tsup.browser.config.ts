import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/browser.ts"],
  format: ["esm"],
  outDir: "browser-dist",
  clean: true,
  splitting: false,
  sourcemap: false,
  noExternal: ["@uaf/core", "pdf-lib", "@pdf-lib/fontkit", "zod"],
});
