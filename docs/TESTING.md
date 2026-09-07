# Testing Commands

Pastry 的测试命令分成三类：日常开发、UI/人工验证、发布验证。最常用的是第一组。

## 日常开发

改完代码后优先跑这一组：

```bash
mise run check
```

`check` 顺序执行文档校验、shell 语法、设计 token、带覆盖率测试、覆盖率门槛和 release 编译。各项也可单独运行：

- `mise run test:coverage`：运行全部单元测试并生成 coverage 数据。
- `mise run coverage`：检查线覆盖率门槛，默认 20%。必须紧跟 coverage 测试运行，之后如果又跑了普通 build/test，coverage 数据可能会过期。
- `mise run build:release`：确认 release 编译可过。

只想快速跑单测时：

```bash
mise run test
```

按测试类过滤：

```bash
mise run test -- --filter StoreManagerTests
mise run test -- --filter ClipboardCardSnapshotTests
mise run test -- --filter UpdateCheckerTests
mise run test -- --filter SelectionStateTests
mise run test -- --filter OverlayInteractionModelTests
```

### 交互与载荷防回归（建议改相关代码时跑）

```bash
mise run test -- --filter SelectionStateTests
mise run test -- --filter OverlayInteractionModelTests
mise run test -- --filter DragPayloadBuilderTests
mise run test -- --filter UpdateInstallScriptBuilderTests
mise run test -- --filter AppIconProviderTests
```

| 测试类 | 覆盖场景 |
|--------|----------|
| `SelectionStateTests` | 键盘/鼠标选择、⌘ toggle、⇧ 区间、边界 |
| `OverlayInteractionModelTests` | 修饰键合并、空白 clear 约定、**竖滚不映射横向**、侧轮 delta 规范化与连续像素滚动、⌘ 角标 |
| `DragPayloadBuilderTests` | 多选文本/链接/文件载荷、http→https、混选链接规则 |
| `UpdateInstallScriptBuilderTests` | 更新脚本 shell 引用与非法版本号 |
| `AccessibilityIdentifiersTests` | a11y id 稳定与唯一 |
| `ClipboardItemTests` | SourceFormat 迁移、segments、身份 |
| `AppIconProviderTests` | 含 `cachedIcon` 首帧缓存命中 |
| `NetworkAccessPolicyTests` | 远程 URL / 短格式与十进制 IPv4 / `.local` / 重定向 / Content-Length |
| `DisplayModeTests` | 卡片展示类型：text/link/file/missing/mixedMedia |
| `FTSQueryBuilderTests` | FTS5 MATCH 引号转义与多词 AND |
| `BoundedRemoteResourceLoaderTests` | 预览下载重定向、响应和流式字节上限 |
| `PasteboardWriterTests` | 独立 pasteboard 写回（非 general） |
| `MenuBarMenuFactoryTests` | 菜单结构与快捷键 |
| `ClipboardSearchTests` | `filtered(by:)` content / linkTitle / favoriteNote / appName |

**不适合单测（靠 smoke / 人工）**：SwiftUI 视图手势树、NSPanel 层级、真系统剪贴板、真辅助功能弹窗、Live 网络抓取。

剪贴板单元测试必须使用独立实例，不能读写 `NSPasteboard.general`：

```swift
let pasteboard = NSPasteboard.withUniqueName()
```

真实通用剪贴板会触发后台运行的 Pastry 监听器、播放提示音并污染用户当前内容，只能由明确标注的 smoke 或人工流程使用。

## 文档检查

```bash
mise run docs:check
```

使用系统 Swift / Foundation，不引入第三方包、不联网，也不写项目文件。每次先运行内存自测，再检查 README、AGENTS 与 docs 下 Markdown 的内联文件链接、仓库边界、模块/ADR 索引和读取入口。示例代码块不参与检查；不支持完整 Markdown 语法，不检查网页可达性、标题锚点或内容是否符合源码。文档语义仍需对照源码与测试审阅。

## 脚本语法检查

CI 和 `mise run lint:scripts` 共用同一个检查入口：

```bash
mise run lint:scripts
```

新增或移动 shell 脚本时，同步 `scripts/check_shell.sh` 的清单。

## Coverage

生成并检查 coverage：

```bash
mise run test:coverage
mise run coverage
```

指定临时门槛：

```bash
mise run coverage -- 20
mise run coverage -- 25
```

当前 CI 门槛是 20%。这是防止明显倒退的保守门槛，不代表目标覆盖率上限。

## Snapshot Tests

普通 `mise run test` 会跳过 snapshot。验证卡片 PNG 基线：

```bash
mise run snapshot:test
```

更新 snapshot PNG 基线：

```bash
mise run snapshot:record
```

基线文件在：

```text
Tests/PastryTests/__Snapshots__/*.png
```

如果验证失败，测试会写出：

```text
Tests/PastryTests/__Snapshots__/__Failures__/*.actual.png
Tests/PastryTests/__Snapshots__/__Failures__/*.expected.png
```

这些失败图片用于本地对比，不应提交。

## Network-Dependent Tests

更新下载相关的真实网络测试默认跳过。需要显式开启：

```bash
mise run test:network
```

这类测试依赖网络和远端响应，不适合作为每次本地必跑项。

## UI / Smoke

本机冒烟检查会部署开发版、填充剪贴板样本、尝试唤出面板并保存截图：

```bash
mise run smoke
```

常用参数：

```bash
mise run smoke -- --skip-deploy
mise run smoke -- --skip-populate
mise run smoke -- --skip-hotkey
```

产物位置：

```text
dist/smoke/<timestamp>/
```

`mise run smoke` 会自动检查 Pastry 进程、截图文件、截图尺寸，以及唤起前后画面是否发生变化。关键检查失败时脚本会以非 0 退出；通过后仍保留人工验证清单，用来确认卡片内容、右键菜单和菜单栏行为。

只填充剪贴板样本：

```bash
mise run populate
```

注意：`mise run populate` 会写系统剪贴板；Pastry 运行中会捕获这些样本。文本、URL、HTML、RTF 和文件样本只需系统工具；生成图片样本还需要 Python Pillow（`python3 -m pip install Pillow`）。

## Performance Checks

跑一次本机性能基准：

```bash
mise run bench
```

保存或对比基线：

```bash
mise run bench -- --baseline
mise run bench -- --diff
```

从性能日志生成 p50/p95/p99：

```bash
mise run bench -- --report
mise run bench -- --report-dev
```

`--report` 读取正式版的 `~/Library/Logs/Pastry/perf.log`，`--report-dev` 读取 `~/Library/Logs/Pastry Dev/perf.log`。开发诊断默认关闭，可在设置 → Security → Privacy 打开「开发诊断记录」，同时写入：

- `perf.log`：面板打开 / 粘贴计时
- `usage.json`：功能使用次数累加（收藏、删除、预览、筛选等）
- `runtime.jsonl`：按会话记录启动、数据库、热键、面板、粘贴、更新与 watchdog 等结构化事件

`runtime.jsonl` 达到 5 MB 后自动轮转，最多保留当前文件和三个历史文件。日志不会记录剪贴板内容、搜索词或完整 URL。查看最近日志：

```bash
mise run logs:app -- "Pastry Dev" 80
mise run logs
```

完整说明见 [DIAGNOSTICS.md](DIAGNOSTICS.md)。

或在手动启动二进制时使用：

```bash
PASTRY_DIAGNOSTICS=1 .build/release/Pastry
# 兼容旧环境变量
PASTRY_PERF_LOG=1 .build/release/Pastry
```

## Deploy And Release

开发版部署到 `~/Applications/Pastry Dev.app`：

```bash
mise run deploy
```

生产 DMG：

```bash
mise run release -- 1.2.3
```

仅为验收当前未提交修改而放宽脏工作区检查：

```bash
mise run release -- 1.2.3 --allow-dirty
```

发布到 GitHub Release：

```bash
mise run release -- 1.2.3 --publish
```

`release.sh` 会执行测试、release 构建、签名、DMG 打包和烟测。`--publish` 还会推 tag 并创建 GitHub Release。
两种模式都会在 `.local/logs/release/` 或 `.local/logs/publish/` 保存完整命令输出、阶段耗时和退出码：

```bash
mise run logs:release
mise run logs:publish -- --full
```

## CI Commands

`.github/workflows/tests.yml` 当前执行：

```bash
mise run check
```

`.github/workflows/release-build-verification.yml` 手动触发，核心命令：

```bash
mise run check
```

CI 只验证源码、测试与 release 编译，不持有稳定签名私钥，也不上传正式 DMG。

## Recommended Checklist

日常小改：

```bash
mise run check
```

涉及 UI 卡片：

```bash
mise run test:coverage
mise run coverage
mise run snapshot:test
```

发布前：

```bash
mise run check
mise run snapshot:test
mise run smoke
```
