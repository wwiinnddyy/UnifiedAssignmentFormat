# UAF TypeScript / Node 参考实现

本目录为 UAF v1.0 的 **TypeScript 独立子项目**（pnpm monorepo）。规范见仓库根 [spec/](../../spec/)。

## 安装与构建

```bash
cd implementations/typescript
pnpm install
pnpm build
```

中文字体由依赖 `@fontsource/noto-sans-sc` 自动提供，无需额外下载。

### 依赖与缓存放置 D 盘（推荐）

若 C 盘空间不足，本目录 [`.npmrc`](./.npmrc) 与 [`.pnpmrc`](./.pnpmrc) 指向：

| 用途 | 路径 |
|------|------|
| npm 缓存 | `D:\dev\npm-cache` |
| pnpm store | `D:\dev\pnpm-store` |

```powershell
npm config set cache "D:\dev\npm-cache" --location=user
npx pnpm@9.15.0 config set store-dir "D:\dev\pnpm-store" --global
```

## CLI

```bash
# 从字段生成 PDF（输出路径自定）
pnpm exec uaf create -o homework.pdf \
  --subject 数学 \
  --date 2026-05-19 \
  --content "完成课本第45页第1、2题" \
  --tags "必做;几何"

# 从仓库根 examples 中的 CSV 生成
pnpm exec uaf create -o homework.pdf --from ../../examples/uaf_payload.sample.csv

pnpm exec uaf extract homework.pdf -o payload.csv
pnpm exec uaf validate homework.pdf
```

退出码：`0` 成功，`1` 用户错误，`2` 非 UAF / 损坏文件。

## SDK

```typescript
import { extractUafPayload } from "@uaf/pdf";
import { readFile } from "node:fs/promises";

const pdfBytes = new Uint8Array(await readFile("homework.pdf"));
const payload = await extractUafPayload(pdfBytes);
```

## 包结构

| 包 | 说明 |
|----|------|
| `@uaf/core` | 类型、Zod 校验、CSV 编解码 |
| `@uaf/pdf` | PDF 卡片渲染、附件嵌入与提取 |
| `uaf` | 命令行工具 |

## 开发

```bash
pnpm test
pnpm run generate:sample   # 写入仓库根 examples/
```

## 发布到 npm

```bash
pnpm build
# 在 packages/core、packages/pdf、packages/cli 分别 publish
```

## 许可证

GPL-3.0-or-later — 见 [LICENSE](../../LICENSE)。
