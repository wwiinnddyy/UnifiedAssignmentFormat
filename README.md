# 统一作业展示与交换格式 (UAF)

UAF v1.0 将作业信息编码为 **单页 PDF 作业卡片**（人类可读），并在 PDF 内嵌 `uaf_payload.csv`（机器可读），实现「表里合一、无缝降级」。

本仓库是 **标准 + 多语言实现** 的集合：规范与共享样例在根目录；各语言的 SDK/CLI 在 [`implementations/`](./implementations/) 下独立维护。

## 规范文档

- [UAF v1.0 总规范](./spec/uaf-v1.0.md)
- [CSV Schema](./spec/csv-schema.md)
- [视觉规范](./spec/visual-spec.md)

## 共享样例

- [examples/uaf_payload.sample.csv](./examples/uaf_payload.sample.csv)
- [examples/sample-homework.html](./examples/sample-homework.html)
- [examples/sample-homework.pdf](./examples/sample-homework.pdf)

## 语言实现

| 语言 | 目录 | 说明 |
|------|------|------|
| **TypeScript / Node** | [implementations/typescript/](./implementations/typescript/) | 参考实现：`@uaf/core`、`@uaf/html`、`@uaf/pdf`、`uaf` CLI |
| **C#** | [implementations/csharp/](./implementations/csharp/) | 规划中 |

详见 [implementations/README.md](./implementations/README.md)。

## 快速开始（TypeScript）

```bash
cd implementations/typescript
pnpm install
pnpm build
pnpm exec uaf render-html -o homework.html --from ../../examples/uaf_payload.sample.csv
pnpm exec uaf create -o homework.pdf --from ../../examples/uaf_payload.sample.csv
```

安装、CLI、SDK 接入与 npm 发布说明见 [implementations/typescript/README.md](./implementations/typescript/README.md)。

## 平台接入 Pipeline（语言无关）

1. 用户上传 `.pdf`
2. 解析器从 PDF Catalog 的 `/EmbeddedFiles` 读取 `uaf_payload.csv`（**禁止 OCR**）
3. 按 [csv-schema.md](./spec/csv-schema.md) 解析四字段，映射至平台作业模型

## 许可证

GPL-3.0-or-later — 见 [LICENSE](./LICENSE)。
