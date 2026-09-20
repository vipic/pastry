import CSQLCipher
import Foundation
import OSLog

// MARK: - SQLite 数据库管理
// 使用原生 sqlite3 API；vendored SQLCipher 仅作为带 FTS5 的 SQLite 引擎，数据库以明文保存。
//
// ⚠️ 线程安全由 NSRecursiveLock 保证（非 Sendable / nonisolated(unsafe) 压制 Swift 6 检查）。
// 新增任何公开方法必须覆盖完整加锁边界；耗时的文件系统检查应先复制候选，再释放锁。
// StoreManager 的搜索和低频维护会从后台任务调用 DatabaseManager。
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
        reconcileSchema()
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
        reconcileSchema()
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

    private static let clipColumnAdditions: [(name: String, definition: String)] = [
        ("text_annotation", "TEXT"),
        ("image_urls", "TEXT"),
        ("segments", "TEXT"),
        ("is_handoff", "INTEGER DEFAULT 0"),
        ("raw_format_data", "BLOB"),
        ("raw_format_type", "TEXT"),
        ("is_url", "INTEGER DEFAULT 0"),
        ("dedup_key", "TEXT"),
        ("link_title", "TEXT"),
        ("favorite_note", "TEXT"),
        ("favorite_note_updated_at", "REAL"),
        ("file_bookmarks", "BLOB")
    ]

    private func createTables() {
        let clipsSQL = """
        CREATE TABLE IF NOT EXISTS clips (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            content TEXT NOT NULL,
            content_type TEXT NOT NULL,
            app_name TEXT,
            is_favorite INTEGER DEFAULT 0,
            display_count INTEGER DEFAULT 0,
            text_annotation TEXT,
            image_urls TEXT,
            segments TEXT,
            is_handoff INTEGER DEFAULT 0,
            raw_format_data BLOB,
            raw_format_type TEXT,
            is_url INTEGER DEFAULT 0,
            dedup_key TEXT,
            link_title TEXT,
            favorite_note TEXT,
            favorite_note_updated_at REAL,
            file_bookmarks BLOB
        );
        """

        let idxSQL = """
        CREATE INDEX IF NOT EXISTS idx_clips_timestamp ON clips(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_clips_favorite ON clips(is_favorite) WHERE is_favorite = 1;
        CREATE INDEX IF NOT EXISTS idx_clips_type ON clips(content_type);
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
        _ = execute(cleanupTrigger)
        log.info("数据库表初始化完成")
    }

    /// 在事务中协调旧数据库结构：任意语句失败 → 回滚并返回 false。
    /// 不复用 autocommit 的 `execute`；用 sqlite3_exec 直接走 BEGIN/ROLLBACK/COMMIT。
    @discardableResult
    private func runSchemaTransaction(_ label: String, _ block: () -> Bool) -> Bool {
        guard execute("BEGIN IMMEDIATE;") else {
            log.error("结构协调 [\(label, privacy: .public)] 开启事务失败: \(self.lastError)")
            diagnosticsLog.error(
                "数据库结构协调事务启动失败",
                event: "database.schema_transaction.begin_failed",
                metadata: ["operation": label, "error": lastError]
            )
            return false
        }
        let ok = block()
        if ok {
            guard execute("COMMIT;") else {
                log.error("结构协调 [\(label, privacy: .public)] 提交失败: \(self.lastError)")
                diagnosticsLog.error(
                    "数据库结构协调事务提交失败",
                    event: "database.schema_transaction.commit_failed",
                    metadata: ["operation": label, "error": lastError]
                )
                _ = execute("ROLLBACK;")
                return false
            }
            return true
        } else {
            _ = execute("ROLLBACK;")
            log.error("结构协调 [\(label, privacy: .public)] 失败已回滚")
            diagnosticsLog.error(
                "数据库结构协调失败并已回滚",
                event: "database.schema_transaction.rolled_back",
                metadata: ["operation": label]
            )
            return false
        }
    }

    /// 结构事务内执行的语句；失败返回 false（事务会被外层回滚）。
    @discardableResult
    private func schemaExec(_ sql: String) -> Bool {
        execute(sql)
    }

    /// 以实际表结构为事实来源补齐旧数据库，不再依赖会漂移的 `PRAGMA user_version`。
    ///
    /// 新增列只需加入 `clipColumnAdditions`；已有列会跳过，部分完成的旧迁移也可安全恢复。
    private func reconcileSchema() {
        let existingColumns = Set(columnNames(in: "clips"))
        let missingColumns = Self.clipColumnAdditions.filter { !existingColumns.contains($0.name) }

        if !missingColumns.isEmpty {
            let reconciled = runSchemaTransaction("schema-reconciliation") {
                for column in missingColumns {
                    guard schemaExec(
                        "ALTER TABLE clips ADD COLUMN \(column.name) \(column.definition);"
                    ) else {
                        return false
                    }
                }
                return schemaExec("CREATE INDEX IF NOT EXISTS idx_clips_dedup ON clips(dedup_key);")
            }
            guard reconciled else { return }
            diagnosticsLog.notice(
                "旧数据库结构已协调到当前定义",
                event: "database.schema.reconciled",
                metadata: ["column_count": String(missingColumns.count)]
            )
        } else {
            _ = execute("CREATE INDEX IF NOT EXISTS idx_clips_dedup ON clips(dedup_key);")
        }

        _ = execute(Self.semanticIndexTableSQL)
        _ = execute(Self.semanticDeleteTriggerSQL)
        repairFTSSchemaIfNeeded()

        // 所有列和 FTS 表就绪后统一重建同步触发器。
        _ = execute("DROP TRIGGER IF EXISTS trg_clips_fts_delete;")
        _ = execute("DROP TRIGGER IF EXISTS trg_clips_fts_insert;")
        _ = execute("DROP TRIGGER IF EXISTS trg_clips_fts_update;")
        _ = execute(Self.ftsDeleteTriggerSQL)
        _ = execute(Self.ftsInsertTriggerSQL)
        _ = execute(Self.ftsUpdateTriggerSQL)
    }

    /// 修复 FTS 虚拟表仍停留在旧结构的数据库。
    ///
    /// SQLite 创建触发器时不会验证触发器正文引用的 FTS 列；这种不一致会一直潜伏到
    /// 下一次 INSERT / DELETE 才报错，导致主表写入被整个语句回滚。
    private func repairFTSSchemaIfNeeded() {
        guard ftsColumnNames() != ["content", "link_title", "favorite_note"] else { return }

        let repaired = runSchemaTransaction("fts-schema-repair") {
            guard schemaExec("DROP TRIGGER IF EXISTS trg_clips_fts_delete;") else { return false }
            guard schemaExec("DROP TRIGGER IF EXISTS trg_clips_fts_insert;") else { return false }
            guard schemaExec("DROP TRIGGER IF EXISTS trg_clips_fts_update;") else { return false }
            guard schemaExec("DROP TABLE IF EXISTS clips_fts;") else { return false }
            guard schemaExec(Self.latestFTSTableSQL) else { return false }
            return schemaExec(
                "INSERT INTO clips_fts(rowid, content, link_title, favorite_note) "
                    + "SELECT rowid, content, link_title, favorite_note FROM clips;"
            )
        }

        if repaired {
            diagnosticsLog.notice(
                "全文搜索索引结构已自动修复",
                event: "database.fts_schema.repaired"
            )
        }
    }

    private func ftsColumnNames() -> [String] {
        columnNames(in: "clips_fts")
    }

    private func columnNames(in table: String) -> [String] {
        precondition(table == "clips" || table == "clips_fts")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            names.append(String(cString: name))
        }
        return names
    }

    // MARK: - FTS 触发器 SQL（createTables 与迁移复用）
    //
    // 外部 content FTS5 表（content='clips'）的同步必须用 FTS5 的特殊 'delete' 命令，
    // 而非普通 `DELETE FROM clips_fts`。后者会触发 "database disk image is malformed"。
    // 参见 SQLite FTS5 文档 external content tables 章节。

    private static let latestFTSTableSQL = """
    CREATE VIRTUAL TABLE clips_fts USING fts5(
        content,
        link_title,
        favorite_note,
        content='clips',
        content_rowid='rowid',
        tokenize='porter unicode61'
    );
    """

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

    private static let semanticIndexTableSQL = """
    CREATE TABLE IF NOT EXISTS clip_semantics (
        clip_id TEXT PRIMARY KEY,
        summary_zh TEXT NOT NULL,
        summary_en TEXT NOT NULL,
        tags_zh TEXT NOT NULL,
        tags_en TEXT NOT NULL,
        embedding_zh BLOB,
        embedding_en BLOB,
        indexed_at REAL NOT NULL
    );
    """

    private static let semanticDeleteTriggerSQL = """
    CREATE TRIGGER IF NOT EXISTS trg_clips_semantic_delete
    AFTER DELETE ON clips
    BEGIN
        DELETE FROM clip_semantics WHERE clip_id = old.id;
    END;
    """

    // MARK: - CRUD

    /// 列表查询的公共列（不含 raw_format_data BLOB，该字段仅在粘贴时按需加载）。
    /// 文件路径必须完整保留，否则多文件书签无法与原路径一一对应。
    private static let listColumns = """
        id, timestamp, \
        CASE WHEN content_type IN ('fileURL', 'image') THEN content ELSE substr(content, 1, 256) END AS content, \
        content_type, app_name, text_annotation, image_urls, segments, is_favorite, display_count, \
        is_handoff, is_url, link_title, favorite_note, favorite_note_updated_at, file_bookmarks
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
        INSERT OR IGNORE INTO clips (id, timestamp, content, content_type, app_name, text_annotation, image_urls, segments, is_favorite, display_count, is_handoff, raw_format_data, raw_format_type, is_url, dedup_key, link_title, favorite_note, favorite_note_updated_at, file_bookmarks)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
        if let bookmarks = item.fileBookmarks,
           let bookmarkData = try? JSONEncoder().encode(bookmarks) {
            bindBlob(bookmarkData, to: stmt, index: 19)
        } else {
            sqlite3_bind_null(stmt, 19)
        }

        let rc = sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        guard rc == SQLITE_DONE else {
            diagnosticsLog.error(
                "剪贴板记录写入失败",
                event: "database.clip_insert.step_failed",
                metadata: ["result_code": String(rc), "error": lastError]
            )
            return .skipped
        }

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

    /// 删除所有路径当前都不存在的非收藏文件类记录。
    /// 数据库读取和删除分别加锁，文件系统检查不占用数据库锁。
    @discardableResult
    func pruneMissingFileItems(
        pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Int? {
        let candidates: [(id: String, item: ClipboardItem)]

        lock.lock()
        let sql = """
        SELECT id, content, content_type, file_bookmarks
        FROM clips
        WHERE content_type IN ('fileURL', 'image')
          AND is_favorite = 0;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            lock.unlock()
            log.error("失效文件清理查询 prepare 失败: \(self.lastError)")
            return nil
        }
        var loaded: [(String, ClipboardItem)] = []
        var stepResult = sqlite3_step(stmt)
        while stepResult == SQLITE_ROW {
            if let idPointer = sqlite3_column_text(stmt, 0),
               let contentPointer = sqlite3_column_text(stmt, 1),
               let typePointer = sqlite3_column_text(stmt, 2) {
                let bookmarkData = readBlob(from: stmt, column: 3)
                let bookmarks = bookmarkData.flatMap {
                    try? JSONDecoder().decode([Data?].self, from: $0)
                }
                let item = ClipboardItem(
                    content: String(cString: contentPointer),
                    sourceFormat: SourceFormat(storageKey: String(cString: typePointer)),
                    fileBookmarks: bookmarks
                )
                loaded.append((String(cString: idPointer), item))
            }
            stepResult = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        lock.unlock()
        guard stepResult == SQLITE_DONE else {
            log.error("失效文件清理查询失败: \(self.lastError)")
            return nil
        }
        candidates = loaded

        let missingIDs = candidates.compactMap { candidate -> String? in
            let paths = FileLocationResolver.resolvedURLs(for: candidate.item).map(\.path)
            guard !paths.isEmpty, paths.allSatisfy({ !pathExists($0) }) else { return nil }
            return candidate.id
        }
        guard !missingIDs.isEmpty else { return 0 }

        lock.lock()
        defer { lock.unlock() }
        guard execute("BEGIN IMMEDIATE;") else { return nil }
        let deleteSQL = "DELETE FROM clips WHERE id = ? AND is_favorite = 0;"
        var deleteStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else {
            _ = execute("ROLLBACK;")
            return nil
        }
        var deleted = 0
        var deleteFailed = false
        for id in missingIDs {
            sqlite3_reset(deleteStmt)
            sqlite3_clear_bindings(deleteStmt)
            sqlite3_bind_text(deleteStmt, 1, (id as NSString).utf8String, -1, nil)
            guard sqlite3_step(deleteStmt) == SQLITE_DONE else {
                deleteFailed = true
                break
            }
            deleted += Int(sqlite3_changes(db))
        }
        sqlite3_finalize(deleteStmt)
        guard !deleteFailed, execute("COMMIT;") else {
            _ = execute("ROLLBACK;")
            return nil
        }
        if deleted > 0 { lastKey = nil }
        return deleted
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
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return [] }

        // unicode61 不会把连续中文按词切开。自然语言解析可能产出多个中文关键词，
        // 因此不能用包含空格的完整 query 做一次 LIKE；每个词分别匹配，再以 AND 合并。
        let termClause = "(content LIKE ? OR link_title LIKE ? OR favorite_note LIKE ?)"
        let whereClause = Array(repeating: termClause, count: terms.count).joined(separator: " AND ")
        let sql = """
        SELECT \(Self.listColumns)
        FROM clips
        WHERE \(whereClause)
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }

        var bindIndex: Int32 = 1
        for term in terms {
            let pattern = "%\(term)%"
            for _ in 0 ..< 3 {
                sqlite3_bind_text(stmt, bindIndex, (pattern as NSString).utf8String, -1, nil)
                bindIndex += 1
            }
        }
        sqlite3_bind_int(stmt, bindIndex, Int32(limit))

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
        if rc != SQLITE_DONE {
            diagnosticsLog.error(
                "剪贴板记录删除失败",
                event: "database.clip_delete.step_failed",
                metadata: ["result_code": String(rc), "error": lastError]
            )
        }
        if changed > 0 { lastKey = nil }
        return rc == SQLITE_DONE && changed > 0
    }

    /// 清空全部
    @discardableResult
    func clearAll() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard execute("DELETE FROM clips;") else { return false }
        lastKey = nil
        return true
    }

    // MARK: - 本地语义索引

    func semanticIndexProgress() -> (indexed: Int, total: Int) {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT
            COUNT(s.clip_id),
            COUNT(c.id)
        FROM clips c
        LEFT JOIN clip_semantics s ON s.clip_id = c.id
        WHERE c.content_type != 'image' OR COALESCE(c.text_annotation, '') != '';
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return (0, 0) }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (0, 0) }
        return (Int(sqlite3_column_int64(stmt, 0)), Int(sqlite3_column_int64(stmt, 1)))
    }

    /// 只清除可再生成的语义派生数据，不影响任何剪贴板历史。
    @discardableResult
    func clearSemanticIndex() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return execute("DELETE FROM clip_semantics;")
    }

    /// 返回尚未建立语义索引的历史。正文只取有限前缀，避免单条大文本占满模型上下文。
    func semanticIndexInputs(limit: Int = 80) -> [SemanticIndexInput] {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT c.id,
               CASE WHEN c.content_type = 'image'
                    THEN COALESCE(c.text_annotation, '')
                    ELSE substr(c.content, 1, 2400)
               END,
               c.link_title,
               c.favorite_note
        FROM clips c
        LEFT JOIN clip_semantics s ON s.clip_id = c.id
        WHERE s.clip_id IS NULL
          AND (c.content_type != 'image' OR COALESCE(c.text_annotation, '') != '')
        ORDER BY c.timestamp DESC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var inputs: [SemanticIndexInput] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idPointer = sqlite3_column_text(stmt, 0),
                  let id = UUID(uuidString: String(cString: idPointer)),
                  let contentPointer = sqlite3_column_text(stmt, 1)
            else { continue }
            let linkTitle = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let favoriteNote = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            inputs.append(
                SemanticIndexInput(
                    id: id,
                    content: String(cString: contentPointer),
                    linkTitle: linkTitle,
                    favoriteNote: favoriteNote
                )
            )
        }
        return inputs
    }

    @discardableResult
    func upsertSemanticIndex(_ record: SemanticIndexRecord) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        INSERT INTO clip_semantics
            (clip_id, summary_zh, summary_en, tags_zh, tags_en, embedding_zh, embedding_en, indexed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(clip_id) DO UPDATE SET
            summary_zh = excluded.summary_zh,
            summary_en = excluded.summary_en,
            tags_zh = excluded.tags_zh,
            tags_en = excluded.tags_en,
            embedding_zh = excluded.embedding_zh,
            embedding_en = excluded.embedding_en,
            indexed_at = excluded.indexed_at;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (record.clipID.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (record.summaryZH as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (record.summaryEN as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (record.tagsZH.joined(separator: "\n") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (record.tagsEN.joined(separator: "\n") as NSString).utf8String, -1, nil)
        bindBlob(record.embeddingZH, to: stmt, index: 6)
        bindBlob(record.embeddingEN, to: stmt, index: 7)
        sqlite3_bind_double(stmt, 8, Date().timeIntervalSince1970)
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    func semanticIndexRecords(limit: Int = 2_000) -> [StoredSemanticRecord] {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT clip_id, summary_zh, summary_en, tags_zh, tags_en, embedding_zh, embedding_en
        FROM clip_semantics
        ORDER BY indexed_at DESC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        var records: [StoredSemanticRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idPointer = sqlite3_column_text(stmt, 0),
                  let id = UUID(uuidString: String(cString: idPointer))
            else { continue }
            records.append(
                StoredSemanticRecord(
                    clipID: id,
                    summaryZH: sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "",
                    summaryEN: sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "",
                    tagsZH: (sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "").split(separator: "\n").map(String.init),
                    tagsEN: (sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "").split(separator: "\n").map(String.init),
                    embeddingZH: readBlob(from: stmt, column: 5),
                    embeddingEN: readBlob(from: stmt, column: 6)
                )
            )
        }
        return records
    }

    func items(ids: [UUID]) -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = "SELECT \(Self.listColumns) FROM clips WHERE id IN (\(placeholders));"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (offset, id) in ids.enumerated() {
            sqlite3_bind_text(stmt, Int32(offset + 1), (id.uuidString as NSString).utf8String, -1, nil)
        }
        let found = readItems(from: stmt)
        let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
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
            let fileBookmarks: [Data?]? = {
                let data = readBlob(from: stmt, column: 15)
                return data.flatMap { try? JSONDecoder().decode([Data?].self, from: $0) }
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
                fileBookmarks: fileBookmarks,
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

    private func bindBlob(_ data: Data?, to statement: OpaquePointer?, index: Int32) {
        guard let data else {
            sqlite3_bind_null(statement, index)
            return
        }
        _ = data.withUnsafeBytes { pointer in
            sqlite3_bind_blob(
                statement,
                index,
                pointer.baseAddress,
                Int32(data.count),
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            )
        }
    }

    private func readBlob(from statement: OpaquePointer?, column: Int32) -> Data? {
        guard let pointer = sqlite3_column_blob(statement, column) else { return nil }
        let byteCount = Int(sqlite3_column_bytes(statement, column))
        guard byteCount > 0 else { return nil }
        return Data(bytes: pointer, count: byteCount)
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

}
