# 统一作业展示与交换格式 (UAF) v1.0

## 1. 概述

UAF（Unified Assignment Format）是一种面向家校作业场景的文件交换标准。单个 `.pdf` 文件同时承载：

- **展示层（表）**：人类可读的「作业看板卡片」，在任何 PDF 阅读器中均可正常查看与打印。
- **数据层（里）**：机器可读的结构化载荷，以 `uaf_payload.csv` 形式嵌入 PDF 附件，供平台零 OCR 解析。

## 2. 设计哲学：表里合一，无缝降级

| 层级 | 载体 | 受众 | 行为 |
|------|------|------|------|
| 表 | PDF 页面视觉 | 老师、学生、家长 | 微信等环境直接打开即可阅读 |
| 里 | 内嵌 `uaf_payload.csv` | 应用平台 | 从 `/EmbeddedFiles` 提取，导入数据库 |

**无缝降级**：在不支持 UAF 的设备上，用户仍可获得完整视觉体验；仅机器层数据不可用。

## 3. 文件格式

- **扩展名**：`.pdf`
- **页数**：v1.0 严格要求 **单页**
- **目标档案格式**：PDF/A-3（v1.0 参考实现以功能合规为先，完整 conformance 见路线图）
- **内嵌附件**：见 [csv-schema.md](./csv-schema.md) 与本文第 5 节

## 4. 数据 Schema

UAF v1.0 仅包含四个扁平字段，详见 [csv-schema.md](./csv-schema.md)：

| 字段 | 说明 |
|------|------|
| `subject` | 作业科目 |
| `date` | 布置时间（ISO 8601） |
| `content` | 作业正文 |
| `tags` | 标签列表（CSV 中用 `;` 分隔） |

## 5. PDF 内嵌附件

### 5.1 附件名称

固定为 `uaf_payload.csv`（大小写敏感）。

### 5.2 PDF 对象路径

解析器应按以下路径寻址：

```
Catalog → /Names → /EmbeddedFiles → 名称树 → FileSpec(UF: uaf_payload.csv) → /EF → 流
```

### 5.3 编码

- 字节序列：**UTF-8，无 BOM**
- MIME 类型建议：`text/csv`

## 6. 视觉规范

单页电子看板卡片版式见 [visual-spec.md](./visual-spec.md)。

视觉规范 additionally 包含：

- **PDF 导出水印**：页面右下角固定位置须包含标识文本（如「使用 UAF 导出」），表明该 PDF 由 UAF 标准生成。详见 [visual-spec.md §7 PDF 导出水印](./visual-spec.md#7-pdf-导出水印)。
- 水印是 v1.0 合规性检查的可选项，建议解析器在验证时给出提示。

## 7. 平台交换 Pipeline

1. 用户在网页/APP 中上传 `.pdf`
2. 后端解析器读取 PDF Catalog 的 `/EmbeddedFiles`，提取 `uaf_payload.csv`（**禁止 OCR**）
3. 按 CSV 规范解析四字段，映射至平台本地作业模型

## 8. 错误语义

| 情况 | 建议处理 |
|------|----------|
| 无 `/EmbeddedFiles` 或缺少 `uaf_payload.csv` | 视为普通 PDF，仅展示层可用 |
| 附件存在但 CSV 非法 | UAF 损坏，返回校验错误 |
| 页数 ≠ 1 | v1.0 不合规（validate 可警告） |

## 9. 版本与兼容

- 当前版本：**1.0**
- 未来版本应在附件描述或 CSV 扩展列中声明（v1.0 不预留版本列）

## 10. 参考实现

语言相关实现位于 [`implementations/`](../implementations/)：

| 语言 | 目录 | 状态 | 方法 |
|------|------|------|------|
| TypeScript / Node | [`implementations/typescript/`](../implementations/typescript/) | 已实现 | 原生矢量绘制（`@uaf/pdf`）、HTML 渲染（`@uaf/html`）、`uaf` CLI |
| C# | [`implementations/csharp/`](../implementations/csharp/) | 规划中 | — |

共享验收样例：[`examples/`](../examples/)。

许可证：GPL-3.0
