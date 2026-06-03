# UAF HTML 渲染器规范 v1.0

本文档规定 UAF v1.0 的 HTML 渲染方式，包括 HTML 模板结构、CSS 样式、打印为 PDF 的要求，以及与 [`visual-spec.md`](./visual-spec.md) 的视觉对齐。

## 1. 概述

HTML 渲染器是 UAF 的第三种 PDF 导出方法：

1. 将 [`UafPayload`](./csv-schema.md#6-逻辑层映射) 渲染为**自包含的 HTML 文档**（含内联 CSS）。
2. 用户可直接在浏览器中打开 HTML 并打印为 PDF。
3. 可选地，通过 Puppeteer（无头 Chromium）自动将 HTML 转为 PDF，并用 `pdf-lib` 嵌入 `uaf_payload.csv` 附件。

此方法的优势：
- 依赖浏览器的排版引擎，天然支持复杂文本布局与换行。
- 不强制嵌入字体（使用系统字体栈）。
- 用户可手动调整后再打印。

## 2. HTML 模板规范

### 2.1 自包含要求

- 必须是完整的、有效的 **HTML5 文档**（含 `<!DOCTYPE html>`）。
- 所有 CSS 必须内联在 `<style>` 标签中，**不得引用外部样式表**。
- 不得依赖外部图像或字体文件（使用系统字体栈）。

### 2.2 页面尺寸

| 属性 | 值 |
|------|-----|
| 纸张 | A4 |
| 方向 | 纵向（Portrait） |
| 宽度 | `210mm` |
| 高度 | `297mm`（最小高度，内容不超出单页） |
| 页数 | **1**（禁止分页） |

CSS 控制方式：

```css
@page {
  size: A4 portrait;
  margin: 0;
}
```

### 2.3 打印行为控制

```css
@media print {
  body {
    margin: 0;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
}
```

## 3. 视觉对齐

HTML 渲染器的视觉输出必须与 [`visual-spec.md`](./visual-spec.md) 一致。

### 3.1 页面背景

- 颜色：`#F8FAFC`（浅灰蓝）

### 3.2 卡片

| 属性 | 值 |
|------|-----|
| 背景 | `#FFFFFF` |
| 圆角 | `16pt` |
| 边框 | `1pt solid #E2E8F0` |
| 阴影 | `0 2pt 8pt rgba(148, 163, 184, 0.15)`（可选，打印时应保留） |
| 顶边距 | `40pt`（距页面顶部） |
| 左右边距 | `40pt` |
| 内边距 | `24pt` |
| 宽度 | `页面宽度 - 80pt`（即 `210mm - 80pt`） |
| 高度 | 由内容自适应，**不得固定为整页高** |

### 3.3 顶栏

#### 科目胶囊（左侧）

| 属性 | 值 |
|------|-----|
| 背景 | `#2563EB` |
| 文字色 | `#FFFFFF` |
| 字号 | `14pt` |
| 内边距 | `8pt 16pt` |
| 形状 | 胶囊（`border-radius: 9999pt`） |

#### 日期胶囊（右侧）

| 属性 | 值 |
|------|-----|
| 背景 | `#F1F5F9` |
| 文字色 | `#334155` |
| 字号 | `12pt` |
| 内边距 | `6pt 12pt` |
| 形状 | 胶囊 |

#### 日期显示格式

- `dateDisplay: "zh"`（默认）：`YYYY年M月D日`
- `dateDisplay: "iso"`：保持原始 ISO 8601 字符串

### 3.4 正文区

| 属性 | 值 |
|------|-----|
| 字号 | `22pt`（默认） |
| 行高 | `1.5` |
| 字色 | `#0F172A` |
| 对齐 | 左对齐 |
| 顶部间距 | 分隔线下方 `20pt` |

正文中的换行符（`\n`）应渲染为 `<br>`，保留原文换行。

### 3.5 标签区

| 属性 | 值 |
|------|-----|
| 背景 | `#E0E7FF` |
| 文字色 | `#3730A3` |
| 字号 | `11pt` |
| 内边距 | `5pt 10pt` |
| 形状 | 胶囊 |
| chip 间距 | `8pt` |
| 与正文间距 | `20pt` |

若无标签，此区域应完全隐藏（不渲染空容器）。

### 3.6 字体

使用系统默认中文字体栈，**不强制嵌入字体**：

```css
font-family: "Noto Sans SC", "PingFang SC", "Microsoft YaHei",
  "Hiragino Sans GB", "WenQuanYi Micro Hei", sans-serif;
```

## 4. 水印

页面右下角固定位置须包含水印文本，与 [`visual-spec.md` §7](./visual-spec.md#7-pdf-导出水印) 对齐。

| 属性 | 值 |
|------|-----|
| 文本 | `使用 UAF v1.0 导出`（或 `使用 UAF 导出`） |
| 字号 | `10pt` |
| 字色 | `#94A3B8` |
| 透明度 | `50%`（`opacity: 0.5`） |
| 水平位置 | 距右边缘 `40pt` |
| 垂直位置 | 距下边缘 `40pt` |
| 旋转 | `0°`（水平放置） |

实现方式：使用绝对定位（`position: absolute`）的 `<div>`，放置于 `<body>` 内、卡片之外。

## 5. 打印为 PDF 的要求

当用户从浏览器打印 HTML 为 PDF 时，必须满足以下条件以确保输出合规：

### 5.1 浏览器设置

| 设置 | 要求 |
|------|------|
| 纸张尺寸 | A4 |
| 方向 | 纵向 |
| 边距 | 无 / 最小化（由 CSS `@page { margin: 0 }` 控制） |
| 背景图形 | **必须勾选**（否则卡片背景、阴影、颜色丢失） |
| 页眉 | 空 |
| 页脚 | 空 |

### 5.2 单页约束

- 内容量必须控制在单页 A4 内。
- 若正文过长超出页面，允许浏览器自动缩小，但鼓励实现层做内容截断提示。

## 6. HTML → PDF 自动化转换

`@uaf/html` 包提供可选的自动化转换函数 `htmlToPdf()`，使用 **Puppeteer**（无头 Chromium）。

### 6.1 依赖声明

- Puppeteer 声明为 `optionalDependency`。
- 若未安装，调用 `htmlToPdf()` 时抛出错误，提示用户安装。

### 6.2 转换参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `width` | `"210mm"` | 纸张宽度 |
| `height` | `"297mm"` | 纸张高度 |
| `printBackground` | `true` | 是否打印背景图形 |
| `browser` | 新实例 | 可复用的 Puppeteer `Browser` 实例 |

### 6.3 完整 Pipeline

`createUafPdfFromHtml(payload)` 的执行流程：

1. 调用 `validatePayload(payload)` 校验输入。
2. 调用 `serializePayload(validated)` 生成 CSV 字符串。
3. 调用 `renderUafHtml(validated)` 生成 HTML 字符串。
4. 调用 `htmlToPdf(html)` 将 HTML 转为 PDF 字节数组。
5. 用 `pdf-lib` 加载 PDF，调用 `PDFDocument.attach()` 嵌入 CSV。
6. 返回 `pdfDoc.save()` 的字节数组。

## 7. 无障碍与兼容

- 正文 `#0F172A` 与背景 `#F8FAFC` 的对比度 ≈ 12:1，满足 WCAG AAA。
- 水印 `#94A3B8` 与背景 `#F8FAFC` 的对比度 ≈ 1.8:1，避免干扰阅读。
- HTML 模板必须在 Chrome、Edge、Firefox、Safari 的最新版本中正确渲染。

## 8. 与现有实现的对比

| 特性 | `@uaf/pdf`（原生矢量） | `@uaf/html`（HTML 渲染） |
|------|------------------------|--------------------------|
| 排版引擎 | pdf-lib 手动计算 | 浏览器/Chromium 自动排版 |
| 字体 | 需嵌入 Noto Sans SC 子集 | 系统字体栈，无需嵌入 |
| 文件体积 | < 500 KB（含子集字体） | 较小（仅 PDF 本身，无嵌入字体） |
| 依赖 | pdf-lib + fontkit | pdf-lib + 可选 Puppeteer |
| 离线能力 | 完全离线 | Puppeteer 需下载 Chromium |
| 自定义 | 需改代码 | 可手写调整 HTML/CSS 后打印 |