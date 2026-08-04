# UAF 项目 Software Fluency 分析简报

## 范围与历史边界

- **目标项目**: `c:\git\playground\UnifiedAssignmentFormat`
- **历史窗口**: 30 天（5 次提交：`8f8fc6c` → `c42ad02`）
- **项目性质**: UAF v1.0 标准规范 + 三语言参考实现（TypeScript、C#、Flutter/Dart）
- ** tracked 文件**: 151 个；源文件 52 个，测试文件 10 个
- **主要语言**: TypeScript（28 源 / 9 测试）、JavaScript（14 源 / 0 测试）、C#（10 源 / 1 测试）

---

## 一、Context Map（上下文可达性）

**证据**:
- 根目录 [README.md](file:///c:/git/playground/UnifiedAssignmentFormat/README.md) 清晰列出规范文档索引、共享样例路径、三语言快速开始命令和平台接入 Pipeline。
- [spec/](file:///c:/git/playground/UnifiedAssignmentFormat/spec) 目录包含完整的规范文档集：`uaf-v1.0.md`（总规范）、`csv-schema.md`（数据 Schema）、`html-renderer-spec.md`、`visual-spec.md`、`file-integration-standard.md`，以及 `uaf-artifact-manifest.schema.json`（JSON Schema）。
- TypeScript monorepo 使用 pnpm workspace，四个包（`@uaf/core`、`@uaf/html`、`@uaf/pdf`、`uaf` CLI）各有独立 `package.json`，职责清晰。
- 每个语言实现目录有独立 README（`implementations/README.md` 及各语言 README）。

**评估**: 规范→实现→样例的索引链路完整。Agent 可从 README 直达规范、代码和测试。上下文路由良好。

**缺失**: 无架构决策记录（ADR）；无 CONTRIBUTING.md 或变更指南；无跨语言一致性验证的文档说明。

---

## 二、Environment Readiness（环境就绪度）

**证据**:
- **TypeScript**: README 提供 `pnpm install → pnpm build → pnpm test` 完整链路；`engines` 字段锁定 Node ≥ 20；`packageManager` 锁定 pnpm@9.15.0；CI 使用 `pnpm/action-setup@v4` + `actions/setup-node@v4` 精确复现。
- **Flutter/Dart**: README 提供 `dart pub get → dart analyze → dart test` 链路；`pubspec.yaml` 锁定 SDK `>=3.8.0 <4.0.0`；CI 矩阵覆盖 Ubuntu/Windows/macOS + Dart 3.8.0/stable。
- **C#**: 存在 `.sln` 和 `.csproj`（net8.0），但 README 无 C# 快速开始命令，CI 中**无 C# 构建/测试 job**。

**评估**: TypeScript 和 Flutter 的环境就绪度高，CI 可完整复现。C# 实现缺少 CI 覆盖和 README 快速开始指引，Agent 需自行推断构建方式。

**缺失**: C# 无 CI job、无 README 快速开始；无 `doctor` 或诊断命令；无环境重置脚本。

---

## 三、Fast Feedback（快速反馈）

**证据**:
- **TypeScript CI 流水线**（[ci.yml](file:///c:/git/playground/UnifiedAssignmentFormat/.github/workflows/ci.yml)）: install → typecheck (`tsc --noEmit`) → build → generate:sample → verify:sample → package:sample → read:sample-package → test。共 8 个串行步骤，形成「类型检查 → 构建 → 制品生成 → 制品验证 → 单元测试」的完整反馈链。
- **Flutter CI 流水线**: install → analyze → test → web smoke compile → web smoke run → Chrome browser test。覆盖静态分析、单元测试和跨平台浏览器测试。
- **TypeScript 测试**: vitest，超时 60s；包含集成 roundtrip 测试（CSV→PDF→extract→validate）。
- **Flutter 测试**: 6 个测试文件覆盖 model、CSV、HTML、PDF、artifact manifest、artifact package；包含边界条件（BOM 处理、RFC 4180 转义、空文档拒绝、字段约束）。
- **C# 测试**: 单个 `Program.cs` 包含 5 个手写断言（CSV/HTML/PDF/Package roundtrip + 空文档拒绝），无测试框架，通过 `dotnet run` 执行。

**评估**: TypeScript 和 Flutter 的反馈链完整且分层合理。TypeScript 独有的「生成→验证→打包→读取」制品流水线是突出亮点。C# 测试能力薄弱，无框架、无 CI。

**缺失**: 无 lint 步骤用于 C#（`dotnet format`）；无 Flutter `dart format` 在非 web 矩阵的强制检查；无跨语言 payload 一致性测试。

---

## 四、Quality Gates（质量门禁）

**证据**:
- **TypeScript**: `tsc --noEmit` 作为 typecheck 门禁（`strict: true`、`noUnusedLocals`、`noUnusedParameters`）；pnpm build 确保所有包编译通过；`verify:sample` 脚本验证生成制品与源 payload 一致。
- **Flutter**: `dart analyze`（strict-casts、strict-inference、strict-raw-types）+ `dart format --set-exit-if-changed`（仅 web 矩阵）+ `dart test`。
- **Schema 门禁**: `uaf-artifact-manifest.schema.json` 定义了严格的 JSON Schema（`additionalProperties: false`、路径遍历防护正则、SHA-256 格式校验）；`file-integration-standard.md` 定义了完整的读取/打包算法，要求 CSV/HTML/PDF 三方 payload 一致。
- **错误语义**: 规范定义了明确的错误场景（无 EmbeddedFiles、CSV 非法、页数 < 1、HTML 缺少 template），各实现均有对应的异常处理（`UafErrorCode`、`UafException`）。

**评估**: 规则覆盖较全面——类型安全、Schema 校验、制品一致性、错误语义均有机械化检查。TypeScript 的 `verify:sample` 和 Flutter 的 golden file 测试（`repositoryPath('examples/uaf_payload.sample.csv')`）是跨目录验证的亮点。

**缺失**: 无 pre-commit hook；CI 仅在 `main` 分支的 push/PR 触发，无分支保护规则可见证据；C# 无独立质量门禁；无 visual regression 测试（尽管有 visual-spec）。

---

## 五、Change Safety（变更安全）

**证据**:
- **Git 历史**: 30 天内 5 次提交，最大变更为 Flutter 支持引入（`4a3cb07`，~25,000 行新增，含字体数据 `font_data.dart` 17,699 行）和 UI 样式样例补充（`c42ad02`，~19,000 行新增，含多个 PDF 二进制文件）。
- **CI 触发**: push 和 PR 到 `main` 均触发，覆盖 TypeScript 和 Flutter。
- **不可变模型**: Flutter 实现使用不可变值对象（`const` tags、`UnsupportedError` 防止修改），C# 使用 `record` 类型，TypeScript 使用 Zod 校验——三语言均强制值语义。
- **路径遍历防护**: `uaf-artifact-manifest.schema.json` 的 `relativePath` 定义使用正则禁止 `..`、绝对路径、驱动器前缀和 URL。
- **.gitignore**: 覆盖 node_modules、dist、C# bin/obj、Flutter .dart_tool/build，排除字体二进制。

**评估**: 基本变更控制到位——CI 在 main 上有门禁，模型层强制不可变性，manifest 有路径安全约束。但缺少可见的分支保护策略、回滚机制或权限边界文档。

**缺失**: 无 branch protection rules 可见证据；无回滚/恢复文档或脚本；大型二进制文件（PDF 样例、字体数据）直接进入 git 历史，无 LFS；无变更影响分析工具。

---

## 最强能力

1. **规范驱动的多语言一致性**: 以 `spec/` 为单一事实来源，三语言实现共享同一 CSV Schema、错误语义和制品结构，且有 JSON Schema 作为机械化校验基础。
2. **TypeScript 制品验证流水线**: `generate:sample → verify:sample → package:sample → read:sample-package` 形成端到端的「生成→验证→打包→读取」闭环，CI 中自动执行。
3. **Flutter 测试深度**: 覆盖模型约束、CSV 边界（BOM、RFC 4180、行终止符）、HTML 提取、PDF 嵌入、manifest 校验和 package 完整性，测试质量高。
4. **CI 多平台矩阵**: Flutter CI 覆盖 Ubuntu/Windows/macOS × Dart 版本，包含 Web 编译和 Chrome 浏览器测试。

## 核心风险

1. **C# 实现处于 CI 盲区**: 无 CI job、无 README 快速开始、无 lint 门禁。三语言一致性无法在 CI 层面对 C# 进行验证。
2. **大型二进制文件直接入 git**: PDF 样例（每个 100KB–200KB+）和 17,000+ 行字体数据文件未使用 Git LFS，将导致仓库膨胀和 clone 变慢。
3. **无跨语言一致性自动化验证**: 三语言实现应产出相同的 CSV/HTML/PDF，但无 CI step 对比不同语言实现的输出。
4. **30 天窗口内两次大提交占比极高**: Flutter 引入和 UI 样例补充合计新增约 45,000 行，其中绝大部分为字体数据和二进制 PDF，增加了仓库维护负担。

## 测试覆盖概览

| 语言 | 测试框架 | 测试文件 | 覆盖范围 | CI 执行 |
|------|----------|----------|----------|---------|
| TypeScript | vitest | 9+ | core、html、pdf、集成 roundtrip | ✅ |
| Flutter/Dart | test | 6 | model、CSV、HTML、PDF、manifest、package | ✅ |
| C# | 手写断言 | 1 | CSV/HTML/PDF/Package roundtrip + 空文档 | ❌ 无 CI |

## Owner 引用

- **规范层**: `spec/` — 项目维护者
- **TypeScript 实现**: `implementations/typescript/` — monorepo 各包
- **C# 实现**: `implementations/csharp/` — 独立 .NET 项目
- **Flutter 实现**: `implementations/flutter/` — 独立 Dart 包
- **CI**: `.github/workflows/ci.yml` — 项目维护者
- **共享样例**: `examples/` — 跨语言共用

## 缺失证据

- C# 的 CI 覆盖和 README 快速开始
- 跨语言输出一致性验证
- 分支保护策略和回滚机制
- Git LFS 或大文件管理策略
- Pre-commit hook 或本地质量门禁
- 架构决策记录（ADR）
- Visual regression 测试（尽管有 visual-spec.md）

---

## 潜在发现

1. **C# 实现缺乏 CI 和质量门禁**: 三语言实现中，C# 是唯一不在 CI 中构建和测试的语言。`Program.cs` 使用手写断言而非测试框架，无法被 `dotnet test` 发现和执行。这意味着 C# 实现的回归风险完全依赖人工验证，且 Agent 无法通过 CI 获得 C# 变更的行为反馈。证据来源：`.github/workflows/ci.yml` 和 `implementations/csharp/`。

2. **大型二进制和字体数据直接进入 git 历史**: `examples/ark-ui-styles/` 中 5 个 PDF 文件合计超过 1MB，`implementations/flutter/lib/src/font_data.dart` 超过 17,000 行。这些文件未使用 Git LFS 管理，每次 clone 都需下载完整历史。随着更多 UI 样式样例加入，仓库体积将加速增长。证据来源：`git log --stat` 和 `.gitignore`（无 LFS 配置）。

3. **跨语言实现无一致性验证机制**: 三语言实现应产出可互操作的 CSV/HTML/PDF 制品，但 CI 中仅验证各语言自身的 roundtrip。无步骤将 TypeScript 生成的 PDF 交由 C# 或 Flutter 解析，反之亦然。`file-integration-standard.md` 定义了完整的读取算法，但未在 CI 中跨语言执行。证据来源：`spec/file-integration-standard.md` 和 `.github/workflows/ci.yml`。

4. **Flutter 字体数据以源码形式内嵌**: `font_data.dart`（17,699 行）将字体数据编码为 Dart 字节数组直接编译进包。这导致 Dart analyzer 和 IDE 对该文件处理缓慢，且字体更新需要修改源码而非替换资源文件。证据来源：`implementations/flutter/lib/src/font_data.dart`。

---

## 本证据不得支持的断言

- 不得断言本项目存在**分支保护策略**或**强制 code review**——仓库中无可见的 branch protection rules 证据。
- 不得断言 C# 实现**当前可编译或通过测试**——CI 中无 C# job，无法验证当前健康状态。
- 不得断言三语言实现**产出一致**——无跨语言一致性自动化验证。
- 不得断言本项目**交付健康或质量达标**——本分析仅覆盖静态证据，未验证运行时行为、当前 CI 通过状态或实际部署。
- 不得断言仓库体积**已构成问题**——仅可指出趋势和风险，无历史体积数据对比。
- 不得将本分析的任何发现**量化为最终评分或严重程度**——评分和修复建议由 lead 负责。
