# UAF TypeScript / Node 参考实现

本目录为 UAF v1.0 的 **TypeScript 独立子项目**（pnpm monorepo）。规范见仓库根 [spec/](../../spec/)。

## 安装与构建

```bash
cd implementations/typescript
pnpm install
pnpm build
```

默认 PDF 导出采用 `@uaf/html`：先把 UAF payload 渲染为自包含 HTML/CSS 作业卡片，HTML 内部也携带 inert 的 `uaf_payload.csv` 模板，再通过浏览器打印管线生成 PDF，最后用 `pdf-lib` 嵌入 `uaf_payload.csv`。运行时优先复用 Puppeteer；若未安装 Puppeteer，则自动查找系统 Chrome/Edge，也可通过 `UAF_CHROMIUM_EXECUTABLE`、`PUPPETEER_EXECUTABLE_PATH` 或 `CHROME_PATH` 指定浏览器。HTML-to-PDF 路径更适合复杂排版、圆角、阴影、系统字体和浏览器打印预览。

`@uaf/pdf` 仍保留为原生矢量后端：它会按当前作业实际文字生成 PDF 可渲染的 SFNT 字体子集，再用 pdf-lib 绘制页面。没有安装 Puppeteer/Chromium、或需要最小依赖环境时，可通过 CLI 的 `--renderer pdf` 显式使用该后端；不要把 WOFF/WOFF2 直接作为 pdf-lib 的 PDF 字体流使用，否则部分阅读器会显示空白或替代字形。

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
# 从字段生成 PDF（默认使用 HTML-to-PDF 打印管线）
pnpm exec uaf create -o homework.pdf \
  --subject 数学 \
  --date 2026-05-19 \
  --content "完成课本第45页第1、2题" \
  --tags "必做;几何"

# 从仓库根 examples 中的 CSV 生成
pnpm exec uaf create -o homework.pdf --from ../../examples/uaf_payload.sample.csv

# 只生成自包含 HTML，便于浏览器预览、手动调整打印设置或归档展示层
pnpm exec uaf render-html -o homework.html --from ../../examples/uaf_payload.sample.csv

# 无 Chromium 环境可显式使用旧原生 PDF 后端
pnpm exec uaf create -o homework.pdf --from ../../examples/uaf_payload.sample.csv --renderer pdf

pnpm exec uaf extract homework.pdf -o payload.csv
pnpm exec uaf extract-html homework.html -o payload.csv
pnpm exec uaf validate homework.pdf
pnpm exec uaf validate-html homework.html
```

退出码：`0` 成功，`1` 用户错误，`2` 非 UAF / 损坏文件。

## SDK

```typescript
import {
  createUafPdfFromHtml,
  extractUafPayloadFromHtml,
  renderUafHtml,
} from "@uaf/html";
import { extractUafPayload } from "@uaf/pdf";

const html = renderUafHtml({
  subject: "数学",
  date: "2026-05-19",
  content: "完成课本第45页第1、2题",
  tags: ["必做", "几何"],
});
const pdfBytes = await createUafPdfFromHtml({
  subject: "数学",
  date: "2026-05-19",
  content: "完成课本第45页第1、2题",
  tags: ["必做", "几何"],
});

const payload = await extractUafPayload(pdfBytes);
const payloadFromHtml = extractUafPayloadFromHtml(html);
```

## 包结构

| 包 | 说明 |
|----|------|
| `@uaf/core` | 类型、Zod 校验、CSV 编解码 |
| `@uaf/html` | 自包含 HTML 作业卡片渲染、Chromium 打印 PDF、附件嵌入 |
| `@uaf/pdf` | 原生 PDF 矢量卡片渲染、附件嵌入与提取 |
| `uaf` | 命令行工具 |

## 开发

```bash
pnpm test
pnpm run generate:sample   # 写入仓库根 examples/ 下的 CSV、HTML、PDF
pnpm run verify:sample     # 校验 CSV、HTML、PDF 三者 payload 一致
```

若本机以 `pnpm install --no-optional` 安装依赖，HTML-to-PDF 会尝试回退到系统 Chrome/Edge；单元测试通过注入浏览器对象和伪浏览器可执行文件覆盖打印管线，不需要本地下载 Chromium。

## 发布到 npm

```bash
pnpm build
# 在 packages/core、packages/html、packages/pdf、packages/cli 分别 publish
```

## 许可证

GPL-3.0-or-later — 见 [LICENSE](../../LICENSE)。
