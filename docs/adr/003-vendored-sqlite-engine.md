# ADR-003：vendored SQLite 兼容引擎

## 状态

已采纳（2026-09-03 根据当前实现补录，源码基线 `a5691d8`；不是对原始决策会议或完整历史的还原）。

## 背景

Pastry 通过 SQLite C API 保存历史并使用 FTS5，同时需要让旧版本的 SQLCipher 加密数据库能够在升级时导出为明文 SQLite。系统 SQLite 的编译能力不由项目控制，也不提供读取旧 SQLCipher 数据库所需的接口。

## 决策

在仓库中维护由 SQLCipher 源码构建的 `libsqlcipher.a` 和对应头文件，通过 SwiftPM 的 `CSQLCipher` target 链接。新数据库保持明文；SQLCipher 加密 API只用于旧库一次性迁移。

## 当前依据

以下说明当前设计的作用与取舍，不将推断冒充原始选择动机。可核对 [Package.swift](../../Package.swift)、[DatabaseManager](../../Sources/Pastry/Persistence/DatabaseManager.swift)、[旧库迁移器](../../Sources/Pastry/Persistence/LegacyEncryptedDatabaseMigrator.swift) 和 [DatabaseManagerTests](../../Tests/PastryTests/DatabaseManagerTests.swift)。

- 固定启用项目需要的 FTS5 编译能力，不受目标机器系统 SQLite 构建差异影响。
- 保留 `sqlite3_key` 和 `sqlcipher_export`，使旧加密数据库可以原地升级。
- 静态库随仓库 clone 获取，构建过程不需要包管理器或网络下载。
- 业务代码继续使用 SQLite C API，不引入 ORM 或新的数据访问抽象。

## 代价

- 仓库需要维护预编译二进制、头文件和它们的构建说明；目前缺少经核验的可复现构建任务，见[开发维护边界](../DEVELOPMENT.md)。
- 更新 SQLite/SQLCipher 时必须重新验证架构、编译标志、FTS5、旧库迁移和 release 构建。
- 新平台或 CPU 架构需要提供兼容静态库，不能自动依赖系统库兜底。

## 补录时评估的备选方案

- **系统 SQLite**：依赖更少，但无法保证所需编译能力，也无法读取旧 SQLCipher 数据库。
- **运行时继续使用 SQLCipher 加密**：保留旧行为，但会继续承担密钥和设备绑定迁移复杂度；当前产品选择本机明文 SQLite。
- **引入 GRDB 等包**：可以改善 Swift API，但不能消除底层引擎和旧库迁移要求，并增加第三方包依赖。
