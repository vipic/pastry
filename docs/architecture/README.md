# 架构与模块索引

这里记录 Pastry 当前代码如何协作。文档使用普通 Markdown，面向开发者和代码代理；阅读和维护不依赖 Codex、个人 Skill 或 `workspace-meta`。

## 阅读方式

1. 先从下表确定改动涉及的模块。
2. 只读取相关模块文档、关联 ADR 和测试说明。
3. 修改实现后，如果职责、入口、数据流、依赖或不变量发生变化，同步更新对应架构文档。
4. 实质架构选择按 [ADR 维护约定](../adr/README.md)记录；普通修复不强制新增决策。
5. 运行 `mise run docs:check` 后，再按改动风险运行 `mise run check` 及相关人工验收。文档与实现一起审阅、提交。

## 模块

| 模块 | 主要范围 | 当前文档 |
|---|---|---|
| 剪贴板采集与历史 | `Core/`、`Persistence/`、图片缓存和写回 | [剪贴板采集与历史](clipboard-history.md) |
| 浮层与交互 | `UI/Overlay*`、选择、键盘路由、拖拽 | [浮层与交互](overlay.md) |
| 预览与网络资源 | 链接预览、远程图片、Quick Look、网络策略 | [预览与网络资源](previews-network.md) |
| 设置与系统集成 | 应用生命周期、`Settings/`、热键、登录启动、授权 | [设置与系统集成](settings-system.md) |
| 更新与发布 | 更新检查、安装脚本、签名、DMG 和发布 | [更新与发布](update-release.md) |

完整文件清单和目录职责见[项目结构](../PROJECT_STRUCTURE.md)，产品行为见[产品说明](../PRODUCT.md)，验证入口见[测试说明](../TESTING.md)。

## 架构决策

- [ADR-001：SQLite 裸 API vs CoreData/GRDB](../adr/001-sqlite-over-coredata.md)
- [ADR-002：NSPanel Overlay vs SwiftUI Window](../adr/002-nspanel-over-swiftui-window.md)
- [ADR-003：vendored SQLite 兼容引擎](../adr/003-vendored-sqlite-engine.md)

ADR 解释“为什么这样选择”；模块文档只描述当前仍成立的实现和约束。

## 维护边界

- 源码与测试是当前行为的事实来源；模块页是阅读导航，不是另一份规范或代码生成输入。
- 架构页写关键关系、入口和不变量，不复制完整文件树；新增/移动文件时更新[项目结构](../PROJECT_STRUCTURE.md)。
- 模块页标记源码核对基线和已知局限。相关代码变化后只重核受影响断言；无法核实时标注待验证，不机械刷新日期。
- 模块拆分或重命名时同步索引和全部链接，历史通过 Git 查阅；不为了凑模块数量创建空文档。
- 校验器只检查 README、AGENTS 和 docs 中 Markdown 内联文件链接（含图片），以及架构/ADR 索引覆盖；不联网、不检查远端链接和标题锚点，也不能证明源码语义未漂移。
