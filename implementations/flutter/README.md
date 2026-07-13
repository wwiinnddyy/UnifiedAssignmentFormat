# UAF Flutter / Dart 实现

本目录提供 UAF v1.0 的 Flutter 兼容参考实现。核心库使用纯 Dart，可直接用于 Flutter Android、iOS、Windows、macOS、Linux 与 Web；目录和 `.uaf.zip` 文件读写通过独立的 VM/移动端/桌面端入口提供。

## 能力

| 模块 | 能力 |
|------|------|
| `UafAssignment` / `UafDocument` | 不可变数据模型、ISO 8601 日期及字段约束校验 |
| `UafCsv` | UTF-8 无 BOM、RFC 4180、多记录与多行正文编解码 |
| `UafHtml` | 自包含 HTML5 卡片渲染、payload 提取与结构校验 |
| `UafPdf` | 原生字节级多页 PDF、按文档嵌入 Noto Sans SC TrueType 子集、可选择中文、水印、附件嵌入/提取与校验 |
| `UafArtifactManifest` | 平台中立的 manifest JSON 解析、语义约束和便携路径校验（含 Flutter Web） |
| `UafArtifactPackage` | `.uaf` 目录和 `.uaf.zip` 创建/读取、资源限额、路径安全、CRC-32、SHA-256 与三载体一致性校验 |

## 接入 Flutter

在应用的 `pubspec.yaml` 中引用本目录或发布后的包：

```yaml
dependencies:
  unified_assignment_format:
    path: ../UnifiedAssignmentFormat/implementations/flutter
```

平台无关 API 使用主入口：

```dart
import 'package:unified_assignment_format/unified_assignment_format.dart';

final document = UafDocument(<UafAssignment>[
  UafAssignment(
    subject: '数学',
    date: '2026-05-19',
    content: '完成课本第45页第1、2题',
    tags: const <String>['必做', '几何'],
  ),
]);

final csv = UafCsv.serialize(document);
final html = UafHtml.render(document);
final pdfBytes = UafPdf.create(document);

final fromCsv = UafCsv.parse(csv);
final fromHtml = UafHtml.extractPayload(html);
final fromPdf = UafPdf.extractPayload(pdfBytes);
```

在 Android、iOS、桌面端或 Dart VM 中读写整合包时使用 IO 入口：

```dart
import 'package:unified_assignment_format/unified_assignment_format_io.dart';

final package = UafArtifactPackage.create(document);
package.writeDirectory('homework.uaf');
package.writeZip('homework.uaf.zip');

final verified = UafArtifactPackage.read('homework.uaf.zip');
print(verified.payload.length);
```

处理不受信任或较大的包时，可以传入 `UafPackageReadLimits`，并使用 worker isolate 版本避免在 UI isolate 中执行 ZIP 解压、hash 和三载体校验：

```dart
const limits = UafPackageReadLimits();

final verifiedFile = await UafArtifactPackage.readAsync(
  'homework.uaf.zip',
  limits: limits,
);
final verifiedBytes = await UafArtifactPackage.fromBytesAsync(
  package.toZipBytes(),
  limits: limits,
);
```

同步的 `read`、`readDirectory`、`readZip`、`fromBytes` 和对应异步 API 都接受相同的 limits。默认配置限制 ZIP 输入大小、manifest 和单条目大小、条目数量、总解压字节数、压缩比以及路径深度，用于防止异常内存分配和 ZIP bomb。

`UafArtifactPackage.read(...)` 会验证 manifest 版本和角色、相对路径安全、文件集合、ZIP 头与 CRC-32、字节数、SHA-256，以及 CSV、HTML、PDF 三处恢复出的 payload 是否完全一致。Flutter Web 不提供文件系统和 artifact package 入口，但可使用主入口处理 CSV、HTML、PDF 字节以及 manifest JSON。

Flutter Web 或其他平台中立代码可直接执行完整 manifest 语义校验：

```dart
final manifest = UafArtifactManifest.parseValidated(manifestJson);
```

## PDF 字体与依赖

SDK 在 `lib/src/font_data.dart` 中携带经 zlib 压缩的 Noto Sans SC 400 源字体数据。`UafPdf.create(...)` 只收集当前文档实际使用的字符，生成并嵌入逐文档 TrueType 子集和 `ToUnicode` 映射，因此输出 PDF 自包含且中文文本可选择、可提取。字体来源、版权和 SIL Open Font License 1.1 见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) 与 [`NotoSansSC-LICENSE.txt`](NotoSansSC-LICENSE.txt)。

若文档包含该字体未覆盖的字符，`UafPdf.create(...)` 会抛出 `invalidPayload` 并指出 Unicode 码位，而不会把正式展示层静默替换成 `?`。调用方可据此更换文本或选择具备相应字体覆盖的渲染管线。

`pubspec.yaml` 将 `pdf` 限制在 `>=3.11.3 <3.13.0`，即经过验证的 3.11–3.12 版本范围。字体子集生成同时依赖导出的 `TtfParser` 和包内部的 `TtfWriter`；后者不属于稳定公共 API，因此依赖设置了明确上界。扩展到 3.13 或更高版本前，必须重新运行 PDF 生成、中文文本提取和浏览器/VM 回归测试。

## 验证 API

`UafHtml.validate(html)` 与 `UafPdf.validate(bytes)` 返回非抛出式结果，适合上传预检。直接提取 API 使用带稳定 `UafErrorCode` 的 `UafException`：

- `invalidCsv` / `invalidPayload`
- `noPayload`（普通 PDF/HTML，没有 UAF payload）
- `corruptPdf` / `invalidHtml`
- `invalidPackage` / `hashMismatch`

## 开发与验收

```powershell
cd implementations/flutter
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
dart compile js tool/web_smoke.dart -o build/web_smoke.js
dart run example/unified_assignment_format_example.dart
```

测试覆盖共享 `examples/` 黄金样例、跨实现 PDF 提取、CSV/HTML/PDF 往返、分页、非法输入、ZIP/目录包、hash 篡改与路径穿越防护。

许可证：GPL-3.0-or-later，见随包发布的 [`LICENSE`](LICENSE)。
