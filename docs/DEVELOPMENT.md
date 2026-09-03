# Development

本文档记录 Pastry 的本地开发、构建、签名和命令入口。发布流程见 [RELEASE.md](RELEASE.md)，测试命令见 [TESTING.md](TESTING.md)。

## 环境要求

- macOS 26+
- Swift 6.0+（`Package.swift` tools-version 6.0；语言模式暂钉 Swift 5，见包清单注释）
- Xcode Command Line Tools
- mise（统一任务入口；先用 `mise tasks` 查看命令）

项目不依赖第三方包管理下载；带 FTS5 的 SQLite 兼容静态库已 vendored 到仓库内。

### SQLite 兼容静态库维护边界

`Sources/CSQLCipher/libsqlcipher.a` 是随仓库提供的 SQLite 兼容引擎；新数据库保持明文，同时保留旧 SQLCipher 加密库迁移能力。日常 clone、编译和测试不需要重新生成此静态库，也不需要个人代理配置。

仓库目前没有经过核验的、可重现该二进制的独立构建任务。不要把历史构建命令当作已验证配方。更新前需要补齐源码版本与校验值、目标架构、SDK、编译标志和可重复运行的 mise 任务，并同步更新头文件；FTS5 和旧加密库 API 必须保留。更新后运行 `mise run check`，重点检查 FTS5 与旧库迁移测试。选择依据及这一维护代价见 [ADR-003](adr/003-vendored-sqlite-engine.md)。

## 快速部署开发版

```bash
git clone https://github.com/vipic/pastry.git
cd pastry
mise run deploy
```

`deploy.sh` 会编译 debug 版本、组装并签名 `~/Applications/Pastry Dev.app`，然后启动应用。
每次执行都会把完整输出、每个阶段和子命令耗时、退出码写入 `.local/logs/deploy/`。查看最近一次摘要：

```bash
mise run logs:deploy
```

## 代码签名

macOS 的辅助功能权限绑定到应用签名。Pastry 必须使用稳定代码签名：自签名代码签名证书或开发者账号证书都可以；不要使用 ad-hoc 签名。ad-hoc 每次重新编译都可能改变代码身份，导致辅助功能授权反复失效。

脚本默认使用证书名 `Nekutai`。如果你想用自己的证书名，通过环境变量覆盖：

```bash
export CODESIGN_IDENTITY="Your Certificate Name"
```

创建自签名证书：

```text
Keychain Access -> 证书助理 -> 创建证书
名称: Nekutai
身份类型: 自签名根
证书类型: 代码签名
```

证书缺失、签名失败或显式设置 `CODESIGN_IDENTITY="-"` 时，`deploy.sh` 和 `release.sh` 会直接停止，不会改用 ad-hoc。

## 本地构建

只确认 debug 编译：

```bash
mise run build
```

只确认 release 编译：

```bash
mise run build:release
```

这只会生成 SwiftPM 可执行文件，不会组装 `.app` 或 DMG。完整发布包请使用：

```bash
mise run release -- 1.2.3
```

## 本机冒烟

```bash
mise run smoke
```

脚本会部署开发版、填充剪贴板样本、唤出面板，并把截图和日志保存到 `dist/smoke/`。它不进 CI，适合发布前人工确认菜单栏、面板和卡片行为。

## 开发工具

面向开发、测试和诊断的辅助工具统一放在 `scripts/`：

```text
scripts/
├── bench.sh               # 性能基准与 perf.log 报告
├── populate_clipboard.sh  # 写入本机测试样本（图片样本需 Pillow）
├── smoke.sh               # 部署、填充样本并截图
├── check_shell.sh         # 仓库全部 shell 语法检查
├── check_docs.swift       # 离线文档链接、仓库边界与索引校验
├── check_coverage.sh      # 覆盖率门槛
├── check_design_tokens.sh # UI token 防回潮检查
├── diagnostics.sh         # 应用和本地命令日志查看
└── tasks/                 # mise 复杂任务的普通 shell 实现
```

根目录只保留两个主要工作流入口：`deploy.sh` 和 `release.sh`。

## mise 入口

开发和 CI 通过同一组 mise 任务执行常用命令：

```bash
mise run check
mise run docs:check
mise run deploy
mise run smoke
mise run release-auto
```

`mise tasks` 可查看全部入口。常用任务还包括 `test`、`test:coverage`、`bench`、`logs`、`snapshot:test`、`version:next` 和 `publish`；参数通过 `--` 传给底层脚本。`mise` 只是命令面板，真实实现仍在 SwiftPM、根目录工作流脚本和 `scripts/` 中。

## 项目结构

完整的逐文件树形说明见 [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)。

```text
Sources/Pastry/
├── Core/           # ClipboardItem 模型、剪贴板监听
├── Persistence/    # SQLite 数据库、StoreManager
├── UI/             # 面板、卡片、菜单、预览
└── Utils/          # 热键、图标、常量、更新检查
```

当前架构、模块边界和历史决策见[架构与模块索引](architecture/README.md)；代码代理的工作约束见 [AGENTS.md](../AGENTS.md)。
运行时和本地命令日志的字段、隐私边界及排查方法见 [DIAGNOSTICS.md](DIAGNOSTICS.md)。
