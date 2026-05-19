# UAF C# 实现（规划中）

本目录将提供与 [UAF v1.0 规范](../../spec/uaf-v1.0.md) 对齐的 .NET 参考实现，**不依赖** TypeScript 实现，仅以 `spec/` 与根目录 `examples/` 为验收基准。

## 规划能力

| 模块 | 职责 |
|------|------|
| `Uaf.Core` | `UafPayload` 模型、CSV 序列化/反序列化（RFC 4180）、字段校验 |
| `Uaf.Pdf` | 单页作业卡片 PDF 生成；从 `/EmbeddedFiles` 提取 `uaf_payload.csv`（无 OCR） |

## 规划 API（草案）

```csharp
public sealed record UafPayload(string Subject, string Date, string Content, IReadOnlyList<string> Tags);

UafPayload UafCsv.Parse(string csv);
string UafCsv.Serialize(UafPayload payload);

byte[] UafPdf.Create(UafPayload payload);
UafPayload UafPdf.Extract(byte[] pdfBytes);
```

## 验收

- 能读取 [examples/uaf_payload.sample.csv](../../examples/uaf_payload.sample.csv) 与 [examples/sample-homework.pdf](../../examples/sample-homework.pdf)
- 与 [implementations/typescript](../typescript/) 生成的 PDF 在机器层字段上等价（允许展示层字体差异）

## 许可证

GPL-3.0-or-later — 见仓库根 [LICENSE](../../LICENSE)。
