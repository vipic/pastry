# 剪贴板采集与历史架构

> 核对日期：2026-09-03；源码基线：`a5691d8`。静态实现快照，非真实剪贴板验收记录。存储选择见 [ADR-001：SQLite 裸 API vs CoreData/GRDB](../adr/001-sqlite-over-coredata.md) 和 [ADR-003：vendored SQLite 兼容引擎](../adr/003-vendored-sqlite-engine.md)。

## 职责与边界

本模块负责检测系统剪贴板变化、识别内容格式和来源、过滤敏感内容、生成 `ClipboardItem`、持久化历史、全文搜索、去重及自动保留。卡片渲染和面板交互属于浮层模块；跨应用粘贴由浮层调用 `PasteboardWriter` 完成。

## 关键类型

- `ClipboardMonitor`：轮询 `NSPasteboard.general.changeCount`，过滤变更并按格式生成记录。
- `ClipboardMonitorReaders`：解析文本、URL、RTF、HTML、图片和文件 URL。
- `ClipboardItem`：记录格式、标签、来源、Handoff、原始格式数据、图文段和去重身份。
- `ImageCacheManager`：保存图片原图、缩略图和映射，处理缓存淘汰。
- `DatabaseManager`：封装 SQLite C API、schema 迁移、FTS5、CRUD、去重与保留策略。
- `LegacyEncryptedDatabaseMigrator`：把旧 SQLCipher 数据库一次性转换为明文 SQLite。
- `StoreManager`：主线程上的可观察状态，连接监听器、数据库、搜索筛选和 UI。
- `HistoryRetentionPolicy`：校验最大条数和保留天数设置。

## 采集数据流

1. `ClipboardMonitor` 使用 50 ms `Timer` 轮询 `changeCount`，并注册到主 RunLoop 的 `.common` mode，避免菜单、拖拽或滚动期间暂停。
2. 发现新变更后立即记录当前 `NSWorkspace.shared.frontmostApplication`。如果 pasteboard 含 1Password 自定义类型，则把来源覆盖为 1Password。
3. 命中排除 bundle ID 或 `org.nspasteboard.ConcealedType` 时直接跳过。Handoff 类型会标记远程来源并清空普通应用名。
4. 内容按用户意图优先级解析：文件 URL、网页 URL、图片、HTML、RTF、纯文本。图片的磁盘写入和富文本解析在后台任务完成，最终回到主线程发布。
5. `StoreManager` 注册的 `ClipboardMonitor.onNewItem` 回调接收记录，交给 `DatabaseManager` 去重和写入，再刷新最近历史、筛选来源和统计。

采集不使用全局 `CGEvent` tap，也不需要 Input Monitoring 或 Accessibility 权限。Accessibility 只在模拟跨应用粘贴时请求。

## 自身写入与监听暂停

Pastry 写回或清空系统剪贴板时必须协调监听器：

- `suspend()` / `resume()` 使用计数器，允许嵌套调用；只能在主线程调用。
- `ignoreCurrentChange()` 把当前 `changeCount` 标记为自身写入，避免粘贴动作被重新收集并播放复制音效。
- `syncChangeCount()` 在清空后同步游标，避免下一次 poll 把空剪贴板误判为外部复制。
- 应用内复制入口可以立即播放反馈，但仍允许监听器解析和入库；对应 `changeCount` 只跳过重复音效。

## 去重与搜索

`ClipboardItem.dedupKey` 是历史去重身份。文本、RTF 和 HTML 的等价文本可以共享身份；图片、文件 URL 和带不同图文段或附注的内容保持区分。

数据库发现已有相同 key 时会删除旧记录并重新插入，把条目移动到最新位置，同时保留收藏和场景备注。没有历史记录但同一 key 在 5 秒内连续出现时，会跳过快速重复。

搜索优先使用外部内容 FTS5 表，索引内容、链接标题和场景备注；查询词会逐词转义并以前缀 AND 组合。FTS 无结果或准备失败时降级为 `LIKE`。来源应用等结构化筛选由 `StoreManager` 合并处理。

FTS 表通过 `clips` 的 INSERT、UPDATE、DELETE 触发器同步。外部内容表删除必须使用 FTS5 的特殊 `delete` 命令；普通删除可能损坏索引。启动迁移后会核对 FTS 列并修复曾经出现过的 schema 与 `user_version` 不一致。

## 数据库与旧库迁移

当前 `clips.db` 是明文 SQLite，使用 WAL、`synchronous=NORMAL` 和内存页缓存。SwiftPM 链接仓库内的 `libsqlcipher.a`，但新数据库不调用 `sqlite3_key`；该引擎用于提供固定的 FTS5 能力和读取旧加密库。

数据库访问由 `NSRecursiveLock` 保护。新增或修改任何公开数据库方法时必须保持完整的加锁边界，因为后台搜索会跨线程调用数据库。

只有数据库和相邻 `.key` 同时存在时才进入旧库迁移：

1. 如果数据库本来就是可读明文，尝试删除遗留 `.key` 后结束。
2. 否则读取旧设备绑定密钥，把加密库导出到临时明文数据库并验证可读性。
3. 先把原库移动为备份，再替换为明文库；替换失败时尝试恢复原库。
4. 成功后尝试删除 WAL、SHM、临时备份和 `.key`。恢复及若干清理使用 `try?`，不能保证文件系统异常时恢复或删除一定成功；迁移失败后应先检查原库、备份和密钥，不能盲目清理后重试。

源码入口：[ClipboardMonitor](../../Sources/Pastry/Core/ClipboardMonitor.swift)、[StoreManager](../../Sources/Pastry/Persistence/StoreManager.swift)、[DatabaseManager](../../Sources/Pastry/Persistence/DatabaseManager.swift)、[旧库迁移器](../../Sources/Pastry/Persistence/LegacyEncryptedDatabaseMigrator.swift)。迁移与存储回归见 [DatabaseManagerTests](../../Tests/PastryTests/DatabaseManagerTests.swift)。

## 删除与保留

- 用户主动删除可以删除收藏；收藏只豁免自动保留策略。
- 设置页“清空全部”会删除全部历史并清空系统剪贴板。
- 键盘和工具栏删除在历史变空时清空系统剪贴板；右键删除显式关闭这一行为，使用户仍可继续粘贴原内容。
- 保留策略按最大条数和最大天数清理非收藏记录，在数据库启动、设置变化、每 25 次插入以及每 10 分钟执行。
- 数据库另有 50,000 条非收藏记录的触发器安全上限，防止设置或调度异常导致无限增长。

## 主要验证

- `ClipboardMonitorTests`：格式优先级、敏感类型、排除应用、Handoff 和独立 pasteboard 读取。
- `ClipboardItemTests`：格式兼容、图文段、标签和去重身份。
- `DatabaseManagerTests`：schema 迁移、旧加密库转换、CRUD、FTS、去重和保留策略。
- `StoreManagerTests`、`ClipboardSearchTests`：筛选、删除、收藏、搜索合并和内存状态。
- `ImageCacheManagerTests`、`PasteboardWriterTests`：图片缓存和各格式写回。

测试不得使用 `NSPasteboard.general`；每个测试使用 `NSPasteboard.withUniqueName()`，避免触发后台运行的 Pastry 或污染真实剪贴板。完整验证入口见[测试说明](../TESTING.md)。
