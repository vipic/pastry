# Diagnostics

Pastry 将诊断数据分成两条互不依赖的日志链：应用运行日志用于定位用户操作和运行时故障，本地命令日志用于定位编译、打包与发布耗时。两者都只写入本机，不会自动上传。

## 快速查看

```bash
# 列出已有应用日志和最近一次本地命令执行
scripts/diagnostics.sh summary

# 查看应用最近 80 条结构化事件（自动跨越 runtime.jsonl 轮转文件）
scripts/diagnostics.sh app Pastry 80
scripts/diagnostics.sh app "Pastry Dev" 80

# 查看最近一次 workflow 的耗时摘要；--full 包含完整命令输出
scripts/diagnostics.sh command deploy
scripts/diagnostics.sh command release
scripts/diagnostics.sh command publish --full
```

也可以通过 mise 使用相同入口：

```bash
mise run logs
mise run logs:app -- "Pastry Dev" 80
mise run logs:deploy
mise run logs:release -- --full
mise run logs:publish -- --full
```

## 应用运行日志

设置 → Security → Privacy 中的「开发诊断记录」控制本地文件日志。关闭时不写文件；Apple Unified Logging 仍保留非敏感事件，方便使用 Console.app 或 `log` 命令检查崩溃前后的系统上下文。

文件位置：

```text
~/Library/Logs/Pastry/runtime.jsonl
~/Library/Logs/Pastry/perf.log
~/Library/Logs/Pastry/usage.json

# Debug 构建
~/Library/Logs/Pastry Dev/
```

- `runtime.jsonl`：结构化事件，每行一个 JSON 对象，包含时间、session ID、level、category、event、message、可选 duration 和 metadata。
- `perf.log`：供 `scripts/bench.sh --report`（正式版）或 `--report-dev`（开发版）使用的面板与粘贴性能样本。
- `usage.json`：功能使用次数累加，不包含操作内容。

结构化日志覆盖应用生命周期、数据库打开与旧库迁移、剪贴板监听、全局热键、面板显示/关闭、单选和多选粘贴、更新检查及 watchdog。`runtime.jsonl` 到 5 MB 时轮转，保留 `runtime.1.jsonl` 至 `runtime.3.jsonl`。

### 隐私边界

不得记录剪贴板正文、HTML/RTF 内容、搜索词、完整 URL、文件内容或密钥。日志只保留排查所需的状态、数量、类型、耗时、错误类别和非敏感标识。日志模块还会自动将名称含 `clipboard`、`content`、`html`、`pasteboard`、`query`、`rtf`、`text`、`url` 的 metadata 值替换为 `<redacted>`，但调用方仍应优先避免传入敏感字段。

## 本地命令日志

`deploy.sh`、`release.sh` 和 `release.sh --publish` 默认记录日志，不受应用隐私开关影响：

```text
.local/logs/deploy/
.local/logs/release/
.local/logs/publish/
```

每次运行生成独立 run ID，并记录：

- workflow 和 stage 总耗时
- 每条关键命令的参数、耗时和退出码
- mise 自动发布时的下一版本号计算耗时
- 编译、测试、签名、DMG 和 GitHub CLI 的完整输出
- 产物路径与字节数

`.local/` 已被 Git 忽略。日志可能包含本机路径、分支名、tag 和命令输出，分享前仍应人工检查。

## 推荐排查流程

1. 用 `scripts/diagnostics.sh summary` 确认相关日志是否存在。
2. 性能问题先看 command/stage 的 `duration_ms`，定位最慢阶段后再看 `--full` 输出。
3. 应用问题按同一个 `session_id` 串联事件，优先查 `WARNING`、`ERROR`、`CRITICAL`。
4. 将日志时间与代码中的 category/event 对齐；日志事件名应稳定，用户可见文案可以独立调整。
5. 若复现前未开启开发诊断记录，先打开开关再复现；不需要退出应用。
