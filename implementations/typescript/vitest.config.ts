import { defineConfig } from "vitest/config";
import { resolve } from "node:path";

export default defineConfig({
  resolve: {
    alias: {
      "@uaf/core": resolve(__dirname, "packages/core/src/index.ts"),
      "@uaf/pdf": resolve(__dirname, "packages/pdf/src/index.ts"),
    },
  },
  test: {
    include: ["packages/**/*.test.ts", "tests/**/*.test.ts"],
    testTimeout: 60_000,
  },
});
