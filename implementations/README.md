# UAF 语言实现

各语言实现均遵循仓库根目录 [spec/](../spec/) 中的 UAF v1.0 规范，并共享 [examples/](../examples/) 黄金样例。

| 语言 | 目录 | 状态 | 能力 |
|------|------|------|------|
| TypeScript / Node | [typescript/](./typescript/) | 已实现 | CSV 编解码、`uaf` CLI、PDF 生成（原生矢量 `@uaf/pdf` + HTML 渲染 `@uaf/html`）、EmbeddedFiles 提取 |
| C# | [csharp/](./csharp/) | 已实现 | CSV/HTML/PDF、artifact package、共享样例验收 |
| Flutter / Dart | [flutter/](./flutter/) | 已实现 | 跨平台 CSV/HTML/PDF；VM/移动端/桌面端 `.uaf` 与 ZIP 整合包 |

新增语言实现时，请在本表登记，并保持与 `spec/` 一致的四字段 Schema 与 `uaf_payload.csv` 附件名。
