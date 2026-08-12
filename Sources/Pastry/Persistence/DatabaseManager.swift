import CSQLCipher
import Foundation
import OSLog

// MARK: - SQLite 数据库管理
// 使用原生 sqlite3 API；vendored SQLCipher 仅作为带 FTS5 的 SQLite 引擎，数据库以明文保存。
//
// ⚠️ 线程安全由 NSRecursiveLock 保证（非 Sendable / nonisolated(unsafe) 压制 Swift 6 检查）。
// 新增任何公开方法必须手动 lock.lock() / defer { lock.unlock() }，否则 data race。
// 目前只有 StoreManager.performSearch() 从 Task.detached 调用 DatabaseManager。
final class DatabaseManager {

    nonisolated(unsafe) static let shared = DatabaseManager()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "database")
    private let diagnosticsLog = PastryLogger(category: "database")
    private let lock = NSRecursiveLock()

    private var db: OpaquePointer?
    private let dbPath: String

    // 上次插入的去重 key + 时间，5 秒内连续相同才跳过
    private var lastKey: String?
    private var lastKeyTime: Date = .distantPast
    private var insertionsSinceRetentionCleanup = 0
    private var retentionCleanupInterval = 25
    static var maxHistoryItemsForTesting: Int {
        HistoryRetentionPolicy.defaultMaxItems
    }

    private init() {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let dir = AppDirectories.applicationSupportDirectory()
        AppDirectories.ensureDirectory(dir, logCategory: "database")

        dbPath = dir.appendingPathComponent("clips.db").path
        LegacyEncryptedDatabaseMigrator(dbPath: dbPath, log: log).migrateIfNeeded()
        openDatabase()
        createTables()
        runMigrations()
        // 启动时立即执行一次保留策略清理，避免闲置期间旧数据越过保留期而不清理
        enforceHistoryRetention()
        diagnosticsLog.info(
            "数据库初始化完成",
            event: "database.initialization.completed",
                metadata: ["storage": "plaintext"],
            durationMilliseconds: Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
        )
    }

    /// 测试专用：使用临时数据库，不污染生产数据。
    init(dbPath: String) {
        self.dbPath = dbPath
        openDatabase()
        createTables()
        runMigrations()
    }

    /// 测试专用：控制插入时保留策略清理频率。
    func setRetentionCleanupIntervalForTesting(_ interval: Int) {
        retentionCleanupInterval = max(1, interval)
        insertionsSinceRetentionCleanup = 0
    }

    deinit {
        if let db = db {
            sqlite3_close_v2(db)
        }
    }

    // MARK: - 数据库操作

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            diagnosticsLog.error(
                "无法打开数据库",
                event: "database.open.failed",
                metadata: ["error": lastError]
            )
            log.error("无法打开数据库: \(self.dbPath)")
            db = nil
        } else {
            // 开启 WAL 模式，提升并发性能
            execute("PRAGMA journal_mode=WAL")
            execute("PRAGMA synchronous=NORMAL")
            execute("PRAGMA cache_size=-8000")  // 8MB 缓存
            diagnosticsLog.info(
                "数据库已打开",
                event: "database.open.succeeded",
                metadata: ["storage": "plaintext"]
            )
            log.info("数据库已打开: \(self.dbPath)")
        }
    }

    private func createTables() {
        let clipsSQL = """
        CREATE TABLE IF NOT EXISTS clips (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            content TEXT NOT NULL,
            content_type TEXT NOT NULL,
            app_name TEXT,
            is_favorite INTEGER DEFAULT 0,
            display_count INTEGER DEFAULT 0
        );
        """

        let idxSQL = """
        CREATE INDEX IF NOT EXISTS idx_clips_timestamp ON clips(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_clips_favorite ON clips(is_favorite) WHERE is_favorite = 1;
        CREATE INDEX IF NOT EXISTS idx_clips_type ON clips(content_type);
        """

        let ftsSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS clips_fts USING fts5(
            content,
            link_title,
            favorite_note,
            content='clips',
            content_rowid='rowid',
            tokenize='porter unicode61'
        );
        """

        // 安全网触发器：超过 50000 条时强制裁剪（仅非收藏，收藏项永远保留）
        let cleanupTrigger = """
        CREATE TRIGGER IF NOT EXISTS trg_cleanup_old
        AFTER INSERT ON clips
        BEGIN
            DELETE FROM clips WHERE is_favorite = 0 AND rowid IN (
                SELECT rowid FROM clips WHERE is_favorite = 0
                ORDER BY timestamp ASC
                LIMIT MAX(0, (SELECT COUNT(*) FROM clips WHERE is_favorite = 0) - 50000)
            );
        END;
        """

        _ = execute(clipsSQL)
        _ = execute(idxSQL)
        _ = execute(ftsSQL)
        _ = execute(cleanupTrigger)
        _ = execute(Self.ftsDeleteTriggerSQL)
        // INSERT/UPDATE 触发器在 runMigrations() 末尾统一创建，
        // 因为这里 base clips 表还没有 link_title/favorite_note 等列。

        log.info("数据库表初始化完成")
    }

    /// 在事务中执行一段迁移：任意语句失败 → 回滚并返回 false，且不递增 userVersion。
    /// 不复用 autocommit 的 `execute`；用 sqlite3_exec 直接走 BEGIN/ROLLBACK/COMMIT。
    @discardableResult
    private func runMigrationInTransaction(_ label: String, _ block: () -> Bool) -> Bool {
        guard execute("BEGIN IMMEDIATE;") else {
            log.error("迁移 [\(label, privacy: .public)] 开启事务失败: \(self.lastError)")
            diagnosticsLog.error(
                "数据库迁移事务启动失败",
                event: "database.migration_transaction.begin_failed",
                metadata: ["migration": label, "error": lastError]
            )
            return false
        }
        let ok = block()
        if ok {
            guard execute("COMMIT;") else {
                log.error("迁移 [\(label, privacy: .public)] 提交失败: \(self.lastError)")
                diagnosticsLog.error(
                    "数据库迁移事务提交失败",
                    event: "database.migration_transaction.commit_failed",
                    metadata: ["migration": label, "error": lastError]
                )
                _ = execute("ROLLBACK;")
                return false
            }
            return true
        } else {
            _ = execute("ROLLBACK;")
            log.error("迁移 [\(label, privacy: .public)] 失败已回滚")
            diagnosticsLog.error(
                "数据库迁移失败并已回滚",
                event: "database.migration_transaction.rolled_back",
                metadata: ["migration": label]
            )
            return false
        }
    }

    /// 迁移块内执行的语句；失败返回 false（事务会被外层回滚）。
    @discardableResult
    private func migrateExec(_ sql: String) -> Bool {
        execute(sql)
    }

    private func runMigrations() {
        let version = userVersion
        if version < 1 {
            userVersion = 1
        }
        if version < 2, runMigrationInTransaction("v2", { migrateExec("ALTER TABLE clips ADD COLUMN text_annotation TEXT;") }) {
            userVersion = 2
        }
        if version < 3, runMigrationInTransaction("v3", { migrateExec("ALTER TABLE clips ADD COLUMN image_urls TEXT;") }) {
            userVersion = 3
        }
        if version < 4, runMigrationInTransaction("v4", { migrateExec("ALTER TABLE clips ADD COLUMN segments TEXT;") }) {
            userVersion = 4
        }
        if version < 5, runMigrationInTransaction("v5", { migrateExec("ALTER TABLE clips ADD COLUMN is_handoff INTEGER DEFAULT 0;") }) {
            userVersion = 5
        }
        if version < 6, runMigrationInTransaction("v6", {
            guard migrateExec("ALTER TABLE clips ADD COLUMN raw_format_data BLOB;") else { return false }
            return migrateExec("ALTER TABLE clips ADD COLUMN raw_format_type TEXT;")
        }) {
            userVersion = 6
        }
        if version < 7, runMigrationInTransaction("v7", {
            guard migrateExec("ALTER TABLE clips ADD COLUMN is_url INTEGER DEFAULT 0;") else { return false }
            return migrateExec("UPDATE clips SET content_type = 'text', is_url = 1 WHERE content_type = 'url';")
        }) {
            userVersion = 7
        }
        if version < 8, runMigrationInTransaction("v8", {
            guard migrateExec("ALTER TABLE clips ADD COLUMN dedup_key TEXT;") else { return false }
            return migrateExec("CREATE INDEX IF NOT EXISTS idx_clips_dedup ON clips(dedup_key);")
        }) {
            userVersion = 8
        }
        if version < 9, runMigrationInTransaction("v9", { migrateExec("ALTER TABLE clips ADD COLUMN link_title TEXT;") }) {
            userVersion = 9
        }
        if version < 10, runMigrationInTransaction("v10", {
            guard migrateExec("DROP TABLE IF EXISTS clips_fts;") else { return false }
            let ftsSQL = """
            CREATE VIRTUAL TABLE clips_fts USING fts5(
                content,
                link_title,
                content='clips',
                content_rowid='rowid',
                tokenize='porter unicode61'
            );
            """
            guard migrateExec(ftsSQL) else { return false }
            guard migrateExec("INSERT INTO clips_fts(rowid, content, link_title) SELECT rowid, content, link_title FROM clips;") else { return false }
            guard migrateExec("DROP TRIGGER IF EXISTS trg_clips_fts_delete;") else { return false }
            guard migrateExec("DROP TRIGGER IF EXISTS trg_clips_fts_insert;") else { return false }
            guard migrateExec("DROP TRIGGER IF EXISTS trg_clips_fts_update;") else { return false }
            guard migrateExec(Self.ftsDeleteTriggerSQL) else { return false }
            guard migrateExec(Self.ftsInsertTriggerSQL) else { return false }
            return migrateExec(Self.ftsUpdateTriggerSQL)
        }) {
            userVersion = 10
        }
        if version < 11, runMigrationInTransaction("v11", {
            guard migrateExec("ALTER TABLE clips ADD COLUMN favorite_note TEXT;") else { return false }
            guard migrateExec("ALTER TABLE clips ADD COLUMN favorite_note_updated_at REAL;") else { return false }
            guard migrateExec("DROP TABLE IF EXISTS clips_fts;") else { return false }
            let ftsSQL = """
            CREATE VIRTUAL TABLE clips_fts USING fts5(
                content,
                link_title,
                favorite_note,
                content='clips',
                content_rowid='rowid',
                tokenize='porter unicode61'
            );
            """
            guard migrateExec(ftsSQL) else { return false }
            guard migrateExec("INSERT INTO clips_fts(rowid, content, link_title, favorite_note) SELECT rowid, content, link_title, favorite_note FROM clips;") else { return false }
            guard migrateExec("DROP TRIGGER IF EXISTS trg_clips_fts_delete;") else { return false }
            guard migrateExec("DROP TRIGGER IF EXISTS trg_clips_fts_insert;") else { return false }
            guard migrateExec("DROP TRIGGER IF EXISTS trg_clips_fts_update;") else { return false }
            guard migrateExec(Self.ftsDeleteTriggerSQL) else { return false }
            guard migrateExec(Self.ftsInsertTriggerSQL) else { return false }
            return migrateExec(Self.ftsUpdateTriggerSQL)
        }) {
            userVersion = 11
        }

        // 迁移完成后统一重建 FTS 触发器。
        // createTables 和早期迁移创建触发器时，clips 可能还没有全部 FTS 列
        // （如 favorite_note 在 v11 才加入），触发器会因列不存在而静默创建失败。
        // 这里所有列已就绪，统一重建一次保证触发器始终存在。
        _ = execute("DROP TRIGGER IF EXISTS trg_clips_fts_delete;")
        _ = execute("DROP TRIGGER IF EXISTS trg_clips_fts_insert;")
        _ = execute("DROP TRIGGER IF EXISTS trg_clips_fts_update;")
        _ = execute(Self.ftsDeleteTriggerSQL)
        _ = execute(Self.ftsInsertTriggerSQL)
        _ = execute(Self.ftsUpdateTriggerSQL)
    }

    // MARK: - FTS 触发器 SQL（createTables 与迁移复用）
    //
    // 外部 content FTS5 表（content='clips'）的同步必须用 FTS5 的特殊 'delete' 命令，
    // 而非普通 `DELETE FROM clips_fts`。后者会触发 "database disk image is malformed"。
    // 参见 SQLite FTS5 文档 external content tables 章节。

    private static let ftsDeleteTriggerSQL = """
    CREATE TRIGGER IF NOT EXISTS trg_clips_fts_delete
    AFTER DELETE ON clips
    BEGIN
        INSERT INTO clips_fts(clips_fts, rowid, content, link_title, favorite_note)
        VALUES('delete', old.rowid, old.content, old.link_title, old.favorite_note);
    END;
    """
    private static let ftsInsertTriggerSQL = """
    CREATE TRIGGER IF NOT EXISTS trg_clips_fts_insert
    AFTER INSERT ON clips
    BEGIN
        INSERT INTO clips_fts(rowid, content, link_title, favorite_note)
        VALUES (new.rowid, new.content, new.link_title, new.favorite_note);
    END;
    """
    private static let ftsUpdateTriggerSQL = """
    CREATE TRIGGER IF NOT EXISTS trg_clips_fts_update
    AFTER UPDATE ON clips
    BEGIN
        INSERT INTO clips_fts(clips_fts, rowid, content, link_title, favorite_note)
        VALUES('delete', old.rowid, old.content, old.link_title, old.favorite_note);
        INSERT INTO clips_fts(rowid, content, link_title, favorite_note)
        VALUES (new.rowid, new.content, new.link_title, new.favorite_note);
    END;
    """

    // MARK: - CRUD

    /// 列表查询的公共列（不含 raw_format_data BLOB，该字段仅在粘贴时按需加载）
    private static let listColumns = """
        id, timestamp, substr(content, 1, 256) AS content, content_type, app_name, \
        text_annotation, image_urls, segments, is_favorite, display_count, \
        is_handoff, is_url, link_title, favorite_note, favorite_note_updated_at
        """

    enum InsertResult: Equatable {
        case inserted
        /// 去重置顶：旧 id + 从旧记录继承的收藏字段（新复制项本身通常未收藏）
        case replaced(
            oldID: String,
            isPinned: Bool,
            favoriteNote: String?,
            favoriteNoteUpdatedAt: Date?
        )
        case skippedDuplicate
        case skipped
    }

    /// 插入新项（去重）。重复内容会删除旧记录并置顶（新时间戳 + 新来源），
    /// 但保留旧记录的收藏标记与备注。
    @discardableResult
    func insert(_ item: ClipboardItem) -> InsertResult {
        lock.lock()
        defer { lock.unlock() }
        let key = item.dedupKey
        let now = Date()

        // 跨历史去重：查找相同 dedupKey 的旧记录（含收藏字段）
        var oldID: String?
        var preservedPinned = item.isPinned
        var preservedNote = item.favoriteNote
        var preservedNoteUpdatedAt = item.favoriteNoteUpdatedAt
        let findSQL = """
        SELECT id, is_favorite, favorite_note, favorite_note_updated_at
        FROM clips WHERE dedup_key = ? LIMIT 1;
        """
        var findStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, findSQL, -1, &findStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(findStmt, 1, (key as NSString).utf8String, -1, nil)
            if sqlite3_step(findStmt) == SQLITE_ROW {
                oldID = String(cString: sqlite3_column_text(findStmt, 0))
                // 旧记录已收藏则保留；新项若本身带收藏（极少）也 OR 保留
                if sqlite3_column_int(findStmt, 1) != 0 {
                    preservedPinned = true
                }
                if let notePtr = sqlite3_column_text(findStmt, 2) {
                    let oldNote = String(cString: notePtr)
                    if preservedNote == nil || preservedNote?.isEmpty == true {
                        preservedNote = oldNote
                    }
                }
                if sqlite3_column_type(findStmt, 3) != SQLITE_NULL {
                    let oldUpdated = Date(timeIntervalSince1970: sqlite3_column_double(findStmt, 3))
                    if preservedNoteUpdatedAt == nil {
                        preservedNoteUpdatedAt = oldUpdated
                    }
                }
            }
            sqlite3_finalize(findStmt)
        }

        // 有旧记录 → 删除后重新插入（更新时间戳 + 来源）
        if let old = oldID {
            _ = delete(id: old)
        } else if key == lastKey, now.timeIntervalSince(lastKeyTime) < 5 {
            // 5 秒内同 key 且无历史记录 → 真正的快速重复，跳过
            return .skippedDuplicate
        }

        let sql = """
        INSERT OR IGNORE INTO clips (id, timestamp, content, content_type, app_name, text_annotation, image_urls, segments, is_favorite, display_count, is_handoff, raw_format_data, raw_format_type, is_url, dedup_key, link_title, favorite_note, favorite_note_updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("INSERT prepare 失败: \(self.lastError)")
            diagnosticsLog.error(
                "剪贴板记录写入准备失败",
                event: "database.clip_insert.prepare_failed",
                metadata: ["error": lastError]
            )
            return .skipped
        }

        sqlite3_bind_text(stmt, 1, (item.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, item.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, (item.content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (item.sourceFormat.storageKey as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (item.appName as NSString?)?.utf8String ?? nil, -1, nil)
        sqlite3_bind_text(stmt, 6, (item.textAnnotation as NSString?)?.utf8String ?? nil, -1, nil)
        let imageURLsJSON = item.imageURLs.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        sqlite3_bind_text(stmt, 7, (imageURLsJSON as NSString?)?.utf8String ?? nil, -1, nil)
        sqlite3_bind_text(stmt, 8, (item.segmentsJSON as NSString?)?.utf8String ?? nil, -1, nil)
        sqlite3_bind_int(stmt, 9, preservedPinned ? 1 : 0)
        sqlite3_bind_int(stmt, 10, Int32(item.displayCount))
        sqlite3_bind_int(stmt, 11, item.isHandoff ? 1 : 0)
        if let rawData = item.rawFormatData {
            _ = rawData.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 12, ptr.baseAddress, Int32(rawData.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        } else {
            sqlite3_bind_null(stmt, 12)
        }
        if let rawType = item.rawFormatType {
            sqlite3_bind_text(stmt, 13, (rawType as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 13)
        }
        sqlite3_bind_int(stmt, 14, item.tags.isURL ? 1 : 0)
        sqlite3_bind_text(stmt, 15, (key as NSString).utf8String, -1, nil)
        if let lt = item.linkTitle {
            sqlite3_bind_text(stmt, 16, (lt as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 16)
        }
        if let note = preservedNote {
            sqlite3_bind_text(stmt, 17, (note as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 17)
        }
        if let updatedAt = preservedNoteUpdatedAt {
            sqlite3_bind_double(stmt, 18, updatedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 18)
        }

        let rc = sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        guard rc == SQLITE_DONE else { return .skipped }

        // FTS 由 AFTER INSERT 触发器自动同步；保留策略与 INSERT 放在同一事务内，
        // 避免主表插入成功但清理失败时出现部分提交。
        _ = execute("BEGIN IMMEDIATE;")
        enforceHistoryRetentionIfNeeded()
        _ = execute("COMMIT;")

        // 更新去重缓存
        lastKey = key
        lastKeyTime = now

        if let oldID {
            return .replaced(
                oldID: oldID,
                isPinned: preservedPinned,
                favoriteNote: preservedNote,
                favoriteNoteUpdatedAt: preservedNoteUpdatedAt
            )
        }
        return .inserted
    }

    /// 插入热路径上节流执行历史保留策略，避免每次复制都触发 DELETE 查询。
    private func enforceHistoryRetentionIfNeeded() {
        insertionsSinceRetentionCleanup += 1
        guard insertionsSinceRetentionCleanup >= retentionCleanupInterval else { return }
        insertionsSinceRetentionCleanup = 0
        enforceHistoryRetention()
    }

    /// 自动淘汰过期或超出容量的非收藏记录，收藏项不计入上限。
    func enforceHistoryRetention(policy: HistoryRetentionPolicy = .current) {
        lock.lock()
        defer { lock.unlock() }

        if policy.maxAgeDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(policy.maxAgeDays) * 86_400).timeIntervalSince1970
            let ageSQL = "DELETE FROM clips WHERE is_favorite = 0 AND timestamp < ?;"
            var ageStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, ageSQL, -1, &ageStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(ageStmt, 1, cutoff)
                sqlite3_step(ageStmt)
                sqlite3_finalize(ageStmt)
            } else {
                log.error("历史周期清理 prepare 失败: \(self.lastError)")
            }
        }

        let countSQL = """
        DELETE FROM clips
        WHERE is_favorite = 0
          AND id IN (
              SELECT id FROM clips
              WHERE is_favorite = 0
              ORDER BY timestamp DESC
              LIMIT -1 OFFSET ?
          );
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK else {
            log.error("历史记录淘汰 prepare 失败: \(self.lastError)")
            return
        }
        sqlite3_bind_int(stmt, 1, Int32(policy.maxItems))
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    /// 搜索（优先 FTS，fallback LIKE）
    func search(query: String, limit: Int = 100) -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return recent(limit: limit)
        }

        // FTS5 搜索（带前缀通配）
        let ftsSQL = """
        SELECT c.id, c.timestamp, substr(c.content, 1, 256) AS content, c.content_type, c.app_name,
               c.text_annotation, c.image_urls, c.segments, c.is_favorite, c.display_count, c.is_handoff, c.is_url,
               c.link_title, c.favorite_note, c.favorite_note_updated_at
        FROM clips c
        JOIN clips_fts f ON c.rowid = f.rowid
        WHERE clips_fts MATCH ?
        ORDER BY rank
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, ftsSQL, -1, &stmt, nil) == SQLITE_OK else {
            log.error("FTS search prepare 失败: \(self.lastError)")
            return fallbackSearch(query: query, limit: limit)
        }

        // FTS 查询字符串：双引号包裹防操作符注入 + 前缀匹配
        let ftsQuery = Self.ftsMatchQuery(from: query)

        sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        let results = readItems(from: stmt)
        sqlite3_finalize(stmt)

        if !results.isEmpty { return results }
        return fallbackSearch(query: query, limit: limit)
    }

    /// 将用户输入转为 FTS5 MATCH 表达式：逐词双引号转义 + 前缀 `*`，多词以 AND 连接。
    /// 纯字符串变换，可单测，避免操作符注入。
    static func ftsMatchQuery(from query: String) -> String {
        query
            .split(separator: " ")
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " AND ")
    }

    /// LIKE 降级搜索
    private func fallbackSearch(query: String, limit: Int) -> [ClipboardItem] {
        let sql = """
        SELECT \(Self.listColumns)
        FROM clips
        WHERE content LIKE ? OR link_title LIKE ? OR favorite_note LIKE ?
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }

        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (pattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (pattern as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 4, Int32(limit))

        let results = readItems(from: stmt)
        sqlite3_finalize(stmt)
        return results
    }

    /// 最近历史
    func recent(limit: Int = 100) -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT \(Self.listColumns)
        FROM clips
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        let results = readItems(from: stmt)
        sqlite3_finalize(stmt)
        return results
    }

    /// 收藏列表
    func favorites(limit: Int = 200) -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT \(Self.listColumns)
        FROM clips
        WHERE is_favorite = 1
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        let results = readItems(from: stmt)
        sqlite3_finalize(stmt)
        return results
    }

    /// 切换 pin 状态
    @discardableResult
    func togglePin(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE clips SET is_favorite = CASE WHEN is_favorite THEN 0 ELSE 1 END WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)

        let rc = sqlite3_step(stmt)
        let changed = sqlite3_changes(db)
        sqlite3_finalize(stmt)
        return rc == SQLITE_DONE && changed > 0
    }

    /// 直接设置 pin 状态（不 toggle）
    @discardableResult
    func setPin(id: String, pinned: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE clips SET is_favorite = ? WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }

        sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
        sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, nil)

        let rc = sqlite3_step(stmt)
        let changed = sqlite3_changes(db)
        sqlite3_finalize(stmt)
        return rc == SQLITE_DONE && changed > 0
    }

    /// 增加粘贴次数
    func incrementDisplayCount(id: String) {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE clips SET display_count = display_count + 1 WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            log.warning("incrementDisplayCount failed: \(self.lastError)")
        }
        sqlite3_finalize(stmt)
    }

    /// 更新链接预览抓取的页面标题（nil 表示清空）
    func updateLinkTitle(id: String, linkTitle: String?) {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE clips SET link_title = ? WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

        if let lt = linkTitle {
            sqlite3_bind_text(stmt, 1, (lt as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, nil)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            log.warning("updateLinkTitle failed: \(self.lastError)")
        }
        sqlite3_finalize(stmt)
        // FTS 由 AFTER UPDATE 触发器自动同步，无需手动 rebuildFTSRow
    }

    /// 更新场景备注（nil 表示清空；数据库列名沿用 favorite_note 以保持兼容）
    @discardableResult
    func updateFavoriteNote(id: String, note: String?, updatedAt: Date? = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE clips SET favorite_note = ?, favorite_note_updated_at = ? WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }

        if let note {
            sqlite3_bind_text(stmt, 1, (note as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        if note == nil {
            sqlite3_bind_null(stmt, 2)
        } else if let updatedAt {
            sqlite3_bind_double(stmt, 2, updatedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_text(stmt, 3, (id as NSString).utf8String, -1, nil)

        // AFTER UPDATE 触发器会改写 sqlite3_changes 计数（触发器最后一条语句是 FTS INSERT），
        // 无法用 changes 判断 UPDATE 是否命中行。改用 total_changes 差值。
        let totalBefore = sqlite3_total_changes(db)
        let rc = sqlite3_step(stmt)
        let totalDelta = sqlite3_total_changes(db) - totalBefore
        sqlite3_finalize(stmt)
        // FTS 由 AFTER UPDATE 触发器自动同步，无需手动 rebuildFTSRow
        // totalDelta >= 1 表示至少 UPDATE 命中一行（触发器的额外变更只会让 delta 更大）
        return rc == SQLITE_DONE && totalDelta >= 1
    }

    /// 将条目时间戳更新为现在（移动到列表最前）
    func bumpTimestamp(id: String) {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE clips SET timestamp = ? WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, nil)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            log.warning("bumpTimestamp failed: \(self.lastError)")
        }
        sqlite3_finalize(stmt)
    }

    /// 删除单项
    @discardableResult
    func delete(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let sql = "DELETE FROM clips WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("DELETE prepare 失败: \(self.lastError)")
            return false
        }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        let rc = sqlite3_step(stmt)
        let changed = sqlite3_changes(db)
        sqlite3_finalize(stmt)
        if changed > 0 { lastKey = nil }
        return rc == SQLITE_DONE && changed > 0
    }

    /// 清空全部
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        execute("DELETE FROM clips;")
        lastKey = nil
    }

    // MARK: - 统计

    func stats() -> ClipboardStats {
        lock.lock()
        defer { lock.unlock() }
        let total = scalarInt("SELECT COUNT(*) FROM clips;")
        let today = scalarInt("SELECT COUNT(*) FROM clips WHERE timestamp > strftime('%s', 'now', 'start of day') * 1.0;")
        let favs = scalarInt("SELECT COUNT(*) FROM clips WHERE is_favorite = 1;")
        let sizeK = scalarInt("SELECT COALESCE(SUM(LENGTH(content)), 0) / 1024 FROM clips;")

        return ClipboardStats(
            totalItems: total,
            todayItems: today,
            favoriteCount: favs,
            storageSizeKB: sizeK
        )
    }

    // MARK: - 内部方法

    private func syncFTS(_ item: ClipboardItem) {
        let sql = """
        INSERT INTO clips_fts (rowid, content, link_title, favorite_note)
        VALUES ((SELECT rowid FROM clips WHERE id = ?), ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

        sqlite3_bind_text(stmt, 1, (item.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (item.content as NSString).utf8String, -1, nil)
        if let lt = item.linkTitle {
            sqlite3_bind_text(stmt, 3, (lt as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        if let note = item.favoriteNote {
            sqlite3_bind_text(stmt, 4, (note as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    private func rebuildFTSRow(id: String) {
        let deleteSQL = "DELETE FROM clips_fts WHERE rowid = (SELECT rowid FROM clips WHERE id = ?);"
        var deleteStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_step(deleteStmt)
        }
        sqlite3_finalize(deleteStmt)

        let insertSQL = """
        INSERT INTO clips_fts(rowid, content, link_title, favorite_note)
        SELECT rowid, content, link_title, favorite_note FROM clips WHERE id = ?;
        """
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(insertStmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_step(insertStmt)
        sqlite3_finalize(insertStmt)
    }

    private func readItems(from stmt: OpaquePointer?) -> [ClipboardItem] {
        var items: [ClipboardItem] = []

        while !Task.isCancelled, sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = String(cString: sqlite3_column_text(stmt, 0))
            let timestamp = sqlite3_column_double(stmt, 1)
            let content = String(cString: sqlite3_column_text(stmt, 2))
            let typeStr = String(cString: sqlite3_column_text(stmt, 3))
            let appName: String? = {
                guard let ptr = sqlite3_column_text(stmt, 4) else { return nil }
                return String(cString: ptr)
            }()
            let textAnnotation: String? = {
                guard let ptr = sqlite3_column_text(stmt, 5) else { return nil }
                return String(cString: ptr)
            }()
            // image_urls (col 6) 仅用于保留列位置（imageURLs 现从 segments 计算）
            let segmentsJSON: String? = {
                guard let ptr = sqlite3_column_text(stmt, 7) else { return nil }
                return String(cString: ptr)
            }()
            let pinned = sqlite3_column_int(stmt, 8) != 0
            let dispCount = Int(sqlite3_column_int(stmt, 9))
            let isHandoff = sqlite3_column_int(stmt, 10) != 0
            // raw_format_data / raw_format_type 不在列表查询中，粘贴时按需加载
            let isURL = sqlite3_column_int(stmt, 11) != 0
            let linkTitle: String? = {
                guard let ptr = sqlite3_column_text(stmt, 12) else { return nil }
                return String(cString: ptr)
            }()
            let favoriteNote: String? = {
                guard let ptr = sqlite3_column_text(stmt, 13) else { return nil }
                return String(cString: ptr)
            }()
            let favoriteNoteUpdatedAt: Date? = {
                guard sqlite3_column_type(stmt, 14) != SQLITE_NULL else { return nil }
                return Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14))
            }()

            let sourceFormat = SourceFormat(storageKey: typeStr)
            let tags = ContentTags(
                isURL: isURL,
                hasSegments: segmentsJSON != nil,
                isMultiFile: sourceFormat == .fileURL && content.contains("\n"),
                isMissing: false
            )

            let item = ClipboardItem(
                id: UUID(uuidString: idStr) ?? UUID(),
                timestamp: Date(timeIntervalSince1970: timestamp),
                content: content,
                sourceFormat: sourceFormat,
                tags: tags,
                appName: appName,
                isHandoff: isHandoff,
                textAnnotation: textAnnotation,
                linkTitle: linkTitle,
                segmentsJSON: segmentsJSON,
                displayCount: dispCount,
                isPinned: pinned,
                favoriteNote: favoriteNote,
                favoriteNoteUpdatedAt: favoriteNoteUpdatedAt
            )
            items.append(item)
        }

        return items
    }

    /// 查询所有 image 类型条目的 content 路径（供缓存孤儿清理）
    func allImageContentPaths() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT content FROM clips WHERE content_type = 'image';"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var paths = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            paths.insert(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return paths
    }

    /// 按需加载完整 content（列表查询只截断 256 字符，粘贴时取全文）
    func loadFullContent(id: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT content FROM clips WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let result = String(cString: sqlite3_column_text(stmt, 0))
        return result
    }

    /// 按需加载 raw_format_data / raw_format_type（列表查询不含此 BLOB，粘贴时按需获取）
    func loadRawFormatData(id: UUID) -> (data: Data?, type: String?) {
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT raw_format_data, raw_format_type FROM clips WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return (nil, nil) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (nil, nil) }
        let data: Data? = {
            guard let ptr = sqlite3_column_blob(stmt, 0),
                  sqlite3_column_bytes(stmt, 0) > 0
            else { return nil }
            return Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 0)))
        }()
        let type: String? = {
            guard let ptr = sqlite3_column_text(stmt, 1) else { return nil }
            return String(cString: ptr)
        }()
        return (data, type)
    }

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        guard let db else { return false }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let err = errMsg.map { String(cString: $0) } ?? "unknown"
            log.error("SQLite 错误: \(err)\nSQL: \(sql)")
            diagnosticsLog.error(
                "SQLite 执行失败",
                event: "database.execute.failed",
                metadata: ["result_code": String(rc), "error": err]
            )
            sqlite3_free(errMsg)
            return false
        }
        return true
    }

    private func scalarInt(_ sql: String) -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    private var lastError: String {
        guard let db else { return "database is not open" }
        return String(cString: sqlite3_errmsg(db))
    }

    private var userVersion: Int {
        get { scalarInt("PRAGMA user_version;") }
        set { execute("PRAGMA user_version = \(newValue);") }
    }
}
