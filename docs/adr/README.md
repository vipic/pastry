# 架构决策记录

ADR 保存“为什么选择”，[架构索引](../architecture/README.md)保存“当前怎么工作”。两者都是随仓库提交的普通 Markdown，不需要特定模型、插件或会话记录。

## 索引

- [ADR-001：SQLite 裸 API vs CoreData/GRDB](001-sqlite-over-coredata.md)
- [ADR-002：NSPanel Overlay vs SwiftUI Window](002-nspanel-over-swiftui-window.md)
- [ADR-003：vendored SQLite 兼容引擎](003-vendored-sqlite-engine.md)

## 何时记录

涉及模块边界、存储方式、公共契约、安全策略或长期依赖的实质选择才新增 ADR。普通 bug 修复、文案和格式调整不强制写；没有真实比较过的备选方案不要补造。

新文件使用下一个未使用编号和可读名称，包含：状态、背景、决策、理由、代价、实际考虑过的备选方案，以及可核实的源码、测试或提交来源。人工审阅后与实现一同提交，并更新本索引和相关模块链接。

## 演化规则

- 新选择替代旧选择时新增 ADR，写明被替代的编号；旧记录标记“已被 ADR-xxx 替代”并链接新记录，保留当时背景，不重新编号。
- 架构文档只保留当前事实并指向有效 ADR；历史内容通过 Git 和旧 ADR 查阅，不复制到额外 archive。
- 补录历史实现须标注“补录”，注明证据来源和未知动机，不能把源码推断冒充当时已讨论的决定。
- 不保存原始聊天、token 统计、个人路径、密钥或诊断日志。提交正文可以引用 ADR 编号，无需改变 Conventional Commits 格式。
- 有代码或新证据推翻旧文档时先纠正文档；重要选择变化另建 ADR。日期仅表示实际核对时间，不因例行提交自动刷新。

`mise run docs:check` 检查文档文件链接和索引覆盖，不能判断决策的技术正确性。单模块历史可用 `git log -- docs/architecture/<模块>.md docs/adr/` 查询。
