# Pastry — 协作约定

macOS 26+ 剪贴板管理器；SwiftPM + SwiftUI，SQLite 兼容引擎随仓库提供。

## 命令入口

先运行 `mise tasks`。日常验证使用 `mise run check`，文档快速校验使用 `mise run docs:check`。
开发部署使用 `mise run deploy`；发布和真实 UI 验收仅在任务需要且已获授权时执行。
稳定签名证书默认 `Nekutai`，可通过 `CODESIGN_IDENTITY` 显式配置；设置步骤见[开发说明](docs/DEVELOPMENT.md)，正式制品步骤见[发布流程](docs/RELEASE.md)。

## 知识读取与维护

- 编码前从[架构与模块索引](docs/architecture/README.md)确定受影响模块，只读对应专题、ADR 和测试说明，不预加载全库文档。
- 遇到实现与文档冲突时以当前源码、测试为准，核实后纠正文档；无法确认的内容明确标记待验证。
- 职责、入口、数据流、依赖或不变量改变时更新相关架构页；长期架构选择按[ADR 约定](docs/adr/README.md)记录，普通修复不强制写 ADR。
- 文件移动同时更新链接和[项目结构](docs/PROJECT_STRUCTURE.md)。文档随代码在同一变更中审阅，不能依赖个人 Skill、代理目录或相邻私有仓库。
- `docs:check` 只验证文件链接和索引，不替代语义核对和[测试说明](docs/TESTING.md)中的运行验证。

## 项目专属约束

- UI 颜色使用 [PastryPalette](Sources/Pastry/Settings/SettingsChrome.swift)，尺寸、字号、圆角与动效使用 [UIConstants](Sources/Pastry/UI/UIConstants.swift)；禁止在调用点新增 `Color(red:)`。共享 token 至少供两个文件使用，单文件值留在 `private enum Local`，新增值优先复用现有档位。
- 辅助功能授权按粘贴操作需要请求，不为剪贴板轮询或全局热键新增全键盘监听权限。
- 剪贴板单元测试使用独立 pasteboard，不能读写 `NSPasteboard.general`；真实剪贴板只供明确的人工/smoke 验收。
- 新增数据库公开方法保持完整加锁边界；旧库迁移必须保留失败恢复路径。
- 诊断日志不得写入剪贴板正文、搜索词、完整 URL 或密钥，具体边界见[诊断说明](docs/DIAGNOSTICS.md)。

<!-- workspace-policy:start hash=89bb3b3a5f69 -->
## 跨项目统一规则

以下区块由私有 `workspace-meta` 生成；项目专属规则请写在区块外。

### 协作

- [LANG-001] 文档、提交标题和用户可见文案默认使用中文。

### Git

- [GIT-001] 提交使用 Conventional Commits，格式为 `<type>(<optional-scope>): <中文说明>`，标题不以句号结尾。
- [GIT-002] 未明确要求时不要自动提交；需要提交时先检查 status、diff 和近期提交风格。
- [GIT-003] 禁止使用 `--no-verify`，不得擅自 amend，也不得添加 Co-Authored-By 或其他 AI/工具署名 trailer。

### 安全

- [SAFE-001] 保留用户已有和无关改动，不做顺手重构，不使用破坏性 Git 或文件操作。
- [SAFE-002] 不得提交 `.env`、密钥、个人数据、日志、报告、缓存或构建产物。

### 验证

- [VERIFY-001] 修改后运行仓库声明的统一验证入口；涉及页面流程时补跑对应 E2E。

### 依赖

- [DEPS-001] 改动保持最小，不引入项目基线之外的新框架、构建工具或生产依赖，除非用户明确要求。

### 文档

- [DOCS-001] 行为、命令或部署方式变化时同步 README 和相关文档，不保留过期引用。

### 工具链

- [MISE-001] 先运行 `mise tasks` 查看入口；构建、测试和部署统一使用 `mise run <task>`，不绕过 mise 手拼命令。

### macOS 应用

- [SWIFT-001] 使用 SwiftPM executable（swift-tools 6.0）和既有脚本组装应用，不新增 Xcode project。
- [SWIFT-002] 保持 Nekutai 自签名链路与 `com.nekutai.*` bundle id，严禁 ad-hoc 签名。

### macOS 发布

- [SWIFT-003] 新增 shell 脚本纳入 `lint:scripts`；发布继续使用既有 release.sh、DMG 和 GitHub Release 流程。
- [SWIFT-004] 正式发布必须验收最终 DMG：挂载后复制 App 到隔离临时目录，校验 bundle id、版本、关键资源与非 ad-hoc 签名，并完成真实启动冒烟；任一步失败都停止发布。
- [SWIFT-005] 发布说明从上一个正式标签到目标提交生成，保留逐条用户可见变更；release、tag 与同版本制品不得静默覆盖。

### macOS 自更新

- [SWIFT-006] 安装应用内更新前必须校验目标 bundle id、预期版本和代码签名 designated requirement，不得只比较证书名称或 Team ID。
- [SWIFT-007] 替换现有 App 前先备份旧版本；复制失败或安装后版本不符时恢复旧 App，并保留诊断日志和用户可见错误。
<!-- workspace-policy:end -->
