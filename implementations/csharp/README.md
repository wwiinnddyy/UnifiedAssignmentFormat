# UAF C# 实现

本目录提供与 [UAF v1.0 规范](../../spec/uaf-v1.0.md) 对齐的 .NET 参考实现。当前实现只依赖 .NET BCL，不依赖 TypeScript 代码或第三方 NuGet 包，并以 `spec/` 与根目录 `examples/` 为验收基准。

## 能力

| 模块 | 职责 |
|------|------|
| `UafAssignment` / `UafDocument` | 作业记录与非空有序作业集合；逐项校验字段约束 |
| `UafCsv` | UTF-8 / RFC 4180 CSV 序列化与反序列化 |
| `UafHtml` | 自包含 A4 作业卡片 HTML 渲染；从 `<template id="uaf-payload-csv">` 回读 payload |
| `UafPdf` | 多卡片、可分页 PDF 生成；嵌入并读取多行 `uaf_payload.csv` 附件 |
| `UafArtifactPackage` | `.uaf` 目录和 `.uaf.zip` 的导出、读取、manifest 校验、SHA-256 完整性校验 |

## 基本 API

```csharp
var payload = new UafDocument([
    new UafAssignment("数学", "2026-05-19", "完成课本第45页第1、2题。", ["必做"]),
    new UafAssignment("语文", "2026-05-19", "背诵古诗并完成仿写。", ["背诵"])
]);

string csv = UafCsv.Serialize(payload);
UafDocument fromCsv = UafCsv.Parse(csv);

byte[] pdfBytes = UafPdf.Create(payload);
UafDocument fromPdf = UafPdf.ExtractPayload(pdfBytes);

var package = UafArtifactPackage.Create(payload);
package.WriteDirectory("sample-homework.uaf");
package.WriteZip("sample-homework.uaf.zip");

UafArtifactPackage readBack = UafArtifactPackage.Read("sample-homework.uaf");
```

`UafArtifactPackage.Read(...)` 会执行：

- manifest 版本、kind、entrypoints、artifact roles 校验
- 相对路径安全校验，拒绝绝对路径、驱动器前缀、URL、反斜杠和 `..`
- 每个 artifact 的字节数与 SHA-256 校验
- CSV、HTML、PDF 三处恢复出的 payload 一致性校验

## 验收

```powershell
cd implementations/csharp
dotnet restore UnifiedAssignmentFormat.sln
dotnet build UnifiedAssignmentFormat.sln --no-restore
dotnet run --project tests/UnifiedAssignmentFormat.Tests/UnifiedAssignmentFormat.Tests.csproj --no-build --no-restore
```

验收器覆盖：

- CSV 多语言、多行、转义与非法输入
- HTML 渲染和 template 回读
- PDF 生成和附件回读
- `.uaf` 目录与 `.uaf.zip` 往返
- 读取根目录 `examples/sample-homework.uaf`
- artifact 篡改后 hash mismatch

## 许可证

GPL-3.0-or-later — 见仓库根 [LICENSE](../../LICENSE)。
