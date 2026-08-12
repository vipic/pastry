import XCTest
import OSLog
import CSQLCipher
@testable import Pastry

// MARK: - DatabaseManager 测试套件
// 每个测试用例使用独立的临时数据库，互不干扰

final class DatabaseManagerTests: XCTestCase {

    var db: DatabaseManager!
    var tempPath: String!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.historyMaxItems)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.historyMaxAgeDays)
        let tmp = FileManager.default.temporaryDirectory
        tempPath = tmp.appendingPathComponent("pastry-test-\(UUID().uuidString).db").path
        db = DatabaseManager(dbPath: tempPath)
    }

    override func tearDown() {
        db = nil
        if let path = tempPath {
            // 清理 WAL/SHM 文件
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
        }
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.historyMaxItems)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.historyMaxAgeDays)
        super.tearDown()
    }

    // MARK: - 辅助方法

    private func makeItem(
        content: String = "测试文本",
        type: SourceFormat = .text,
        app: String? = "Safari",
        pinned: Bool = false,
        isHandoff: Bool = false,
        timestamp: Date = Date(),
        favoriteNote: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            timestamp: timestamp,
            content: content,
            sourceFormat: type,
            appName: app,
            isHandoff: isHandoff,
            isPinned: pinned,
            favoriteNote: favoriteNote,
            favoriteNoteUpdatedAt: favoriteNote == nil ? nil : timestamp
        )
    }

    /// 断言插入成功（.inserted 或 .replaced 均可）
    private func assertInserted(
        _ item: ClipboardItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = db.insert(item)
        switch result {
        case .inserted, .replaced: break
        default: XCTFail("Expected .inserted or .replaced, got \(result)", file: file, line: line)
        }
    }

    /// 断言插入被去重跳过
    private func assertSkipped(
        _ item: ClipboardItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = db.insert(item)
        switch result {
        case .skippedDuplicate, .skipped: break
        default: XCTFail("Expected .skippedDuplicate or .skipped, got \(result)", file: file, line: line)
        }
    }

    private func enableImmediateRetentionCleanup() {
        db.setRetentionCleanupIntervalForTesting(1)
    }

    private func executeRaw(_ sql: String, on database: OpaquePointer?) {
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }

    // MARK: - 基本 CRUD

    func testPlaintextDatabaseDoesNotCreateKeyFile() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath + ".key"))
    }

    func testLegacyMigratorRemovesStaleKeyBesidePlaintextDatabase() throws {
        let keyPath = tempPath + ".key"
        try Data("obsolete".utf8).write(to: URL(fileURLWithPath: keyPath))

        LegacyEncryptedDatabaseMigrator(
            dbPath: tempPath,
            log: Logger(subsystem: "com.nekutai.pastry.tests", category: "database-migrator")
        ).migrateIfNeeded()

        XCTAssertFalse(FileManager.default.fileExists(atPath: keyPath))
        XCTAssertEqual(db.recent().count, 0)
    }

    func testLegacyMigratorConvertsEncryptedDatabaseToPlaintext() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastry-encrypted-\(UUID().uuidString).db").path
        let keyPath = path + ".key"
        defer {
            for suffix in ["", ".key", "-wal", "-shm", ".plaintext-migrate", ".encrypted-backup"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }

        let key = Data(repeating: 0x2A, count: 32)
        var encrypted: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &encrypted), SQLITE_OK)
        XCTAssertEqual(key.withUnsafeBytes { bytes in
            sqlite3_key(encrypted, bytes.baseAddress, Int32(key.count))
        }, SQLITE_OK)
        executeRaw("CREATE TABLE sample(value TEXT NOT NULL);", on: encrypted)
        executeRaw("INSERT INTO sample VALUES ('preserved');", on: encrypted)
        sqlite3_close(encrypted)
        encrypted = nil
        try LegacyEncryptedDatabaseMigrator.writeLegacyKeyForTesting(key, to: keyPath)

        LegacyEncryptedDatabaseMigrator(
            dbPath: path,
            log: Logger(subsystem: "com.nekutai.pastry.tests", category: "database-migrator")
        ).migrateIfNeeded()

        XCTAssertFalse(FileManager.default.fileExists(atPath: keyPath))
        var plaintext: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(path, &plaintext, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(plaintext, "SELECT value FROM sample;", -1, &statement, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 0)), "preserved")
        sqlite3_finalize(statement)
        sqlite3_close(plaintext)
    }

    /// 插入一条 → recent() 应包含它
    func testInsertAndRetrieve() {
        let item = makeItem(content: "Hello World")
        assertInserted(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].content, "Hello World")
        XCTAssertEqual(items[0].sourceFormat, .text)
        XCTAssertEqual(items[0].appName, "Safari")
    }

    /// 插入多条 → recent() 按时间倒序
    func testInsertMultiple() {
        let a = makeItem(content: "A", timestamp: Date(timeIntervalSince1970: 1))
        let b = makeItem(content: "B", timestamp: Date(timeIntervalSince1970: 2))
        let c = makeItem(content: "C", timestamp: Date(timeIntervalSince1970: 3))

        db.insert(a)
        db.insert(b)
        db.insert(c)

        let items = db.recent()
        XCTAssertEqual(items.count, 3)
        // 最新在前
        XCTAssertEqual(items[0].content, "C")
        XCTAssertEqual(items[1].content, "B")
        XCTAssertEqual(items[2].content, "A")
    }

    /// 插入不同类型的内容
    func testInsertDifferentTypes() {
        let textItem = makeItem(content: "文本", type: .text, timestamp: Date(timeIntervalSince1970: 1))
        let imageItem = makeItem(content: "/tmp/img.png", type: .image, timestamp: Date(timeIntervalSince1970: 2))
        let fileItem = makeItem(content: "/Users/test/file.pdf", type: .fileURL, timestamp: Date(timeIntervalSince1970: 3))

        db.insert(textItem)
        db.insert(imageItem)
        db.insert(fileItem)

        let items = db.recent()
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].sourceFormat, .fileURL)
        XCTAssertEqual(items[1].sourceFormat, .image)
        XCTAssertEqual(items[2].sourceFormat, .text)
    }

    // MARK: - 去重

    /// 相同内容第二次插入 → 替换旧记录并置顶（不产生重复）
    func testDedupReplaceImmediateDuplicate() {
        let item1 = makeItem(content: "相同内容")
        assertInserted(item1)

        let item2 = makeItem(content: "相同内容")
        let result = db.insert(item2)
        switch result {
        case .replaced: break
        default: XCTFail("Expected .replaced, got \(result)")
        }

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
    }

    /// 不同 dedupKey 应正常插入
    func testDedupAllowsDifferent() {
        assertInserted(makeItem(content: "内容A"))
        assertInserted(makeItem(content: "内容B"))
        XCTAssertEqual(db.recent().count, 2)
    }

    // MARK: - 去重置顶

    /// 跨历史去重：复制 A → B → 再次 A，A 应被移到最前且不出现重复
    func testDedupReplaceMovesToTop() {
        let a1 = makeItem(content: "内容A", timestamp: Date(timeIntervalSince1970: 1))
        assertInserted(a1)

        let b = makeItem(content: "内容B", timestamp: Date(timeIntervalSince1970: 2))
        assertInserted(b)

        // 再次复制 A（新 id），应替换旧的 A 并置顶
        let a2 = makeItem(content: "内容A", timestamp: Date(timeIntervalSince1970: 3))
        assertInserted(a2)

        let items = db.recent()
        XCTAssertEqual(items.count, 2, "应只有 2 条，不能出现重复")
        XCTAssertEqual(items[0].content, "内容A", "A 应排到最前")
        XCTAssertEqual(items[1].content, "内容B")
    }

    /// .replaced 返回被替换的旧条目 UUID
    func testDedupReplaceReturnsOldID() {
        let a1 = makeItem(content: "替换测试", timestamp: Date(timeIntervalSince1970: 1))
        _ = db.insert(a1)

        let b = makeItem(content: "中间内容", timestamp: Date(timeIntervalSince1970: 2))
        _ = db.insert(b)

        let a2 = makeItem(content: "替换测试", timestamp: Date(timeIntervalSince1970: 3))
        let result = db.insert(a2)

        switch result {
        case .replaced(let oldID, _, _, _):
            XCTAssertEqual(oldID, a1.id.uuidString, "应返回被替换的旧条目 id")
        default:
            XCTFail("Expected .replaced, got \(result)")
        }
    }

    /// 收藏后再复制相同内容置顶时，应保留收藏标记与备注
    func testDedupReplacePreservesFavoriteAndNote() {
        let original = makeItem(
            content: "收藏后再复制",
            pinned: true,
            timestamp: Date(timeIntervalSince1970: 1),
            favoriteNote: "重要参考"
        )
        assertInserted(original)

        // 模拟剪贴板监控产生的新条目：未收藏、无备注
        let recopied = makeItem(
            content: "收藏后再复制",
            pinned: false,
            timestamp: Date(timeIntervalSince1970: 2),
            favoriteNote: nil
        )
        let result = db.insert(recopied)
        switch result {
        case .replaced(_, let isPinned, let note, _):
            XCTAssertTrue(isPinned, "替换结果应带回收藏状态")
            XCTAssertEqual(note, "重要参考")
        default:
            XCTFail("Expected .replaced, got \(result)")
        }

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].content, "收藏后再复制")
        XCTAssertTrue(items[0].isPinned, "置顶后收藏标记不能丢")
        XCTAssertEqual(items[0].favoriteNote, "重要参考", "置顶后场景备注不能丢")
        XCTAssertEqual(db.favorites().count, 1)
    }

    /// 去重置顶不影响其他无关条目
    func testDedupReplacePreservesOtherItems() {
        let a = makeItem(content: "AAA", timestamp: Date(timeIntervalSince1970: 1))
        let b = makeItem(content: "BBB", timestamp: Date(timeIntervalSince1970: 2))
        let c = makeItem(content: "CCC", timestamp: Date(timeIntervalSince1970: 3))
        assertInserted(a)
        assertInserted(b)
        assertInserted(c)

        // 再次复制 B
        let b2 = makeItem(content: "BBB", timestamp: Date(timeIntervalSince1970: 4))
        assertInserted(b2)

        let items = db.recent()
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].content, "BBB")
        XCTAssertEqual(items[1].content, "CCC")
        XCTAssertEqual(items[2].content, "AAA")
    }

    /// 文本类格式（text/rtf/html）相同内容 → 合并为一条，来源以最后为准
    func testDedupMergesAcrossTextFormats() {
        let textItem = makeItem(content: "hello", type: .text, app: "TextEdit")
        assertInserted(textItem)

        let htmlItem = makeItem(content: "hello", type: .html, app: "Safari")
        let result = db.insert(htmlItem)
        switch result {
        case .replaced: break
        default: XCTFail("Expected .replaced, got \(result)")
        }

        let items = db.recent()
        XCTAssertEqual(items.count, 1, "text 和 html 相同内容应合并")
        XCTAssertEqual(items[0].appName, "Safari", "来源应更新为最后复制的 App")
    }

    /// RTF 和 text 相同内容也应合并
    func testDedupMergesRTFWithText() {
        let rtfItem = makeItem(content: "你好", type: .rtf, app: "Telegram")
        assertInserted(rtfItem)

        let textItem = makeItem(content: "你好", type: .text, app: "Sublime Text")
        let result = db.insert(textItem)
        switch result {
        case .replaced: break
        default: XCTFail("Expected .replaced, got \(result)")
        }

        let items = db.recent()
        XCTAssertEqual(items.count, 1, "RTF 和 text 相同内容应合并")
        XCTAssertEqual(items[0].appName, "Sublime Text", "来源应更新")
    }

    /// text 和 fileURL 即使内容相同也不合并（路径 ≠ 文本）
    func testDedupTextAndFileURLAreSeparate() {
        let file = makeItem(content: "/Users/nekutai/note.txt", type: .fileURL, app: "Finder")
        let text = makeItem(content: "/Users/nekutai/note.txt", type: .text, app: "Sublime Text")

        assertInserted(file)
        assertInserted(text)

        let items = db.recent()
        XCTAssertEqual(items.count, 2, "fileURL 和 text 即使同路径也应独立")
    }

    /// fileURL 和 image 即使底层路径相同也应独立
    func testDedupFileURLAndImageAreSeparate() {
        let path = "/Users/nekutai/Pictures/demo.png"
        let file = makeItem(content: path, type: .fileURL, app: "Finder")
        let image = makeItem(content: path, type: .image, app: "Preview")

        assertInserted(file)
        assertInserted(image)

        let items = db.recent()
        XCTAssertEqual(items.count, 2, "fileURL 和 image 的使用语义不同，应独立保留")
    }

    // MARK: - 删除

    func testDeleteExisting() {
        let item = makeItem()
        db.insert(item)

        XCTAssertTrue(db.delete(id: item.id.uuidString))
        XCTAssertEqual(db.recent().count, 0)
    }

    func testDeleteNonexistent() {
        XCTAssertFalse(db.delete(id: "invalid-uuid"))
    }

    // MARK: - Pin 切换

    func testTogglePinOn() {
        let item = makeItem(pinned: false)
        db.insert(item)

        XCTAssertTrue(db.togglePin(id: item.id.uuidString))

        let favs = db.favorites()
        XCTAssertEqual(favs.count, 1)
        XCTAssertTrue(favs[0].isPinned)
    }

    func testTogglePinOff() {
        let item = makeItem(pinned: true)
        db.insert(item)

        XCTAssertTrue(db.togglePin(id: item.id.uuidString))

        let favs = db.favorites()
        XCTAssertEqual(favs.count, 0)
    }

    func testTogglePinNonexistent() {
        XCTAssertFalse(db.togglePin(id: UUID().uuidString))
    }

    func testUpdateFavoriteNotePersists() {
        let item = makeItem(content: "收藏内容", pinned: true)
        db.insert(item)

        XCTAssertTrue(db.updateFavoriteNote(id: item.id.uuidString, note: "客户 A 的参考方案"))

        let favs = db.favorites()
        XCTAssertEqual(favs.count, 1)
        XCTAssertEqual(favs[0].favoriteNote, "客户 A 的参考方案")
        XCTAssertNotNil(favs[0].favoriteNoteUpdatedAt)
    }

    func testUnpinPreservesFavoriteNote() {
        let item = makeItem(content: "收藏内容", pinned: true, favoriteNote: "之后还会用")
        db.insert(item)

        XCTAssertTrue(db.togglePin(id: item.id.uuidString))
        XCTAssertEqual(db.favorites().count, 0)

        let recent = db.recent()
        XCTAssertEqual(recent.count, 1)
        XCTAssertFalse(recent[0].isPinned)
        XCTAssertEqual(recent[0].favoriteNote, "之后还会用")
    }

    // MARK: - 清空

    func testClearAllRemovesEverything() {
        db.insert(makeItem(content: "A", pinned: true))
        db.insert(makeItem(content: "B", pinned: false))

        db.clearAll()
        XCTAssertEqual(db.recent().count, 0)
        XCTAssertEqual(db.favorites().count, 0)
    }

    // MARK: - 统计

    func testStatsEmpty() {
        let stats = db.stats()
        XCTAssertEqual(stats.totalItems, 0)
        XCTAssertEqual(stats.favoriteCount, 0)
    }

    func testStatsWithItems() {
        db.insert(makeItem(content: "A", pinned: true))
        db.insert(makeItem(content: "BB", pinned: false))
        db.insert(makeItem(content: "CCC", pinned: false))

        let stats = db.stats()
        XCTAssertEqual(stats.totalItems, 3)
        XCTAssertEqual(stats.favoriteCount, 1)
        // content 长度: 1 + 2 + 3 = 6 bytes → 6/1024 = 0 KB（整数除法）
    }

    // MARK: - bumpTimestamp

    func testBumpTimestampMovesToTop() {
        let a = makeItem(content: "旧条目", timestamp: Date(timeIntervalSince1970: 1))
        db.insert(a)

        let b = makeItem(content: "新条目", timestamp: Date(timeIntervalSince1970: 2))
        db.insert(b)

        // bump 旧条目
        db.bumpTimestamp(id: a.id.uuidString)

        let items = db.recent()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].content, "旧条目", "bump 后应排到最前")
        XCTAssertEqual(items[1].content, "新条目")
    }

    // MARK: - incrementDisplayCount

    func testIncrementDisplayCount() {
        let item = makeItem()
        db.insert(item)

        db.incrementDisplayCount(id: item.id.uuidString)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].displayCount, 1)
    }

    func testIncrementDisplayCountMultiple() {
        let item = makeItem()
        db.insert(item)

        db.incrementDisplayCount(id: item.id.uuidString)
        db.incrementDisplayCount(id: item.id.uuidString)
        db.incrementDisplayCount(id: item.id.uuidString)

        let items = db.recent()
        XCTAssertEqual(items[0].displayCount, 3)
    }

    // MARK: - 搜索

    func testSearchEmptyReturnsRecent() {
        db.insert(makeItem(content: "Hello"))
        db.insert(makeItem(content: "World"))

        let results = db.search(query: "")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchFindsMatchingContent() {
        db.insert(makeItem(content: "去买牛奶"))
        db.insert(makeItem(content: "买鸡蛋"))
        db.insert(makeItem(content: "看电影"))

        let results = db.search(query: "牛奶")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].content, "去买牛奶")
    }

    func testSearchFindsFavoriteNote() {
        db.insert(makeItem(content: "https://example.com", pinned: true, favoriteNote: "clientAlpha reference"))
        db.insert(makeItem(content: "普通内容", pinned: true, favoriteNote: "other note"))

        let results = db.search(query: "clientAlpha")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].favoriteNote, "clientAlpha reference")
    }

    func testSearchFindsLinkTitle() {
        let withTitle = ClipboardItem(
            content: "https://example.com/release",
            sourceFormat: .text,
            tags: ContentTags(isURL: true),
            linkTitle: "Pastry Changelog UniqueTitle99"
        )
        let other = ClipboardItem(
            content: "https://example.com/other",
            sourceFormat: .text,
            tags: ContentTags(isURL: true),
            linkTitle: "Unrelated Page"
        )
        assertInserted(withTitle)
        assertInserted(other)

        let results = db.search(query: "UniqueTitle99")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].linkTitle, "Pastry Changelog UniqueTitle99")
    }

    func testFTSMatchQueryEscapesQuotesAndJoinsTokens() {
        XCTAssertEqual(DatabaseManager.ftsMatchQuery(from: "a b"), "\"a\"* AND \"b\"*")
        XCTAssertEqual(
            DatabaseManager.ftsMatchQuery(from: "x\"y"),
            "\"x\"\"y\"*"
        )
    }

    func testSearchNoMatch() {
        db.insert(makeItem(content: "Hello"))
        let results = db.search(query: "XYZ不存在")
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - textAnnotation 持久化

    /// 插入带 textAnnotation 的图片条目 → 读回应包含附注文字
    func testTextAnnotationInsertAndRetrieve() {
        let item = ClipboardItem(
            content: "/tmp/img.png",
            sourceFormat: .image,
            appName: "WeChat",
            textAnnotation: "这是附带的文字"
        )
        assertInserted(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].textAnnotation, "这是附带的文字")
    }

    /// 不带 textAnnotation 的条目 → 读回 nil
    func testTextAnnotationNil() {
        let item = makeItem(content: "普通文本", type: .text)
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].textAnnotation)
    }

    /// 空字符串 textAnnotation 应正常持久化
    func testTextAnnotationEmptyString() {
        let item = ClipboardItem(
            content: "/tmp/img2.png",
            sourceFormat: .image,
            textAnnotation: ""
        )
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items[0].textAnnotation, "")
    }

    // MARK: - segments 持久化

    /// 带 segments 的 HTML 条目插入后读回
    func testSegmentsInsertAndRetrieve() {
        let segs: [ContentSegment] = [
            .image(url: "https://a.com/pic.png"),
            .text("图片后的文字"),
        ]
        let item = ClipboardItem(
            content: "图片后的文字",
            sourceFormat: .html,
            segments: segs
        )
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].segments?.count, 2)
        XCTAssertEqual(items[0].segments?[0].imageURL, "https://a.com/pic.png")
        XCTAssertEqual(items[0].segments?[1].textValue, "图片后的文字")
        // imageURLs 计算属性应从 segments 派生
        XCTAssertEqual(items[0].imageURLs, ["https://a.com/pic.png"])
    }

    /// 不含 segments 的普通条目 → nil
    func testSegmentsNilForNonHTML() {
        let item = makeItem(content: "纯文本", type: .text)
        db.insert(item)

        let items = db.recent()
        XCTAssertNil(items[0].segments)
        XCTAssertNil(items[0].imageURLs)
    }

    /// segments 为空数组 → nil
    func testSegmentsEmptyArray() {
        let item = ClipboardItem(
            content: "无图 HTML",
            sourceFormat: .html,
            segments: []
        )
        db.insert(item)

        let items = db.recent()
        XCTAssertNil(items[0].segments)
    }

    // MARK: - isHandoff 持久化

    /// 插入带 isHandoff 的条目 → 读回应保留标记
    func testIsHandoffInsertAndRetrieve() {
        let item = makeItem(content: "来自 iPhone 的文本", app: nil, isHandoff: true)
        assertInserted(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isHandoff)
        XCTAssertNil(items[0].appName, "Handoff 条目 appName 应为 nil")
    }

    /// 不带 isHandoff 的条目 → 读回 false
    func testIsHandoffDefaultFalse() {
        let item = makeItem(content: "本地复制")
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].isHandoff)
    }

    /// 多种类型 + isHandoff → 全部正确持久化
    func testIsHandoffMultipleTypes() {
        let text = makeItem(content: "text", type: .text, isHandoff: true, timestamp: Date(timeIntervalSince1970: 1))
        db.insert(text)

        let img = makeItem(content: "/tmp/pic.png", type: .image, isHandoff: true, timestamp: Date(timeIntervalSince1970: 2))
        db.insert(img)

        let file = makeItem(content: "/tmp/file.pdf", type: .fileURL, isHandoff: false, timestamp: Date(timeIntervalSince1970: 3))
        db.insert(file)

        let items = db.recent()
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items[0].isHandoff == false)   // file (latest, isHandoff: false)
        XCTAssertTrue(items[1].isHandoff)             // img  (isHandoff: true)
        XCTAssertTrue(items[2].isHandoff)             // text (isHandoff: true)
    }

    /// 搜索也应保留 isHandoff
    func testIsHandoffSurvivesSearch() {
        let item = makeItem(content: "Handoff 搜索测试", isHandoff: true)
        db.insert(item)

        let results = db.search(query: "Handoff")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isHandoff)
    }

    // MARK: - 边界条件

    /// recent(limit:) 应遵守 limit
    func testRecentLimit() {
        for i in 0..<20 {
            let item = makeItem(content: "Item \(i)", timestamp: Date(timeIntervalSince1970: Double(i)))
            db.insert(item)
        }

        let limited = db.recent(limit: 5)
        XCTAssertEqual(limited.count, 5)
    }

    /// 非收藏历史超过上限后自动淘汰最旧记录
    func testHistoryLimitPrunesOldestNonPinnedItems() {
        enableImmediateRetentionCleanup()
        let max = DatabaseManager.maxHistoryItemsForTesting
        for i in 0..<(max + 5) {
            let item = ClipboardItem(
                timestamp: Date(timeIntervalSince1970: Double(i)),
                content: "Item \(i)",
                sourceFormat: .text
            )
            assertInserted(item)
        }

        let items = db.recent(limit: max + 10)
        XCTAssertEqual(items.count, max)
        XCTAssertTrue(items.contains { $0.content == "Item \(max + 4)" })
        XCTAssertFalse(items.contains { $0.content == "Item 0" })
    }

    /// 自动淘汰不删除收藏项
    func testHistoryLimitKeepsPinnedItems() {
        enableImmediateRetentionCleanup()
        let max = DatabaseManager.maxHistoryItemsForTesting
        let pinned = ClipboardItem(
            timestamp: Date(timeIntervalSince1970: 0),
            content: "Pinned oldest",
            sourceFormat: .text,
            isPinned: true
        )
        assertInserted(pinned)

        for i in 0..<max {
            let item = ClipboardItem(
                timestamp: Date(timeIntervalSince1970: Double(i + 1)),
                content: "Item \(i)",
                sourceFormat: .text
            )
            assertInserted(item)
        }

        let items = db.recent(limit: max + 10)
        XCTAssertEqual(items.count, max + 1)
        XCTAssertTrue(items.contains { $0.content == "Pinned oldest" })
    }

    /// 用户设置的历史容量应即时影响非收藏记录淘汰
    func testHistoryLimitUsesUserConfiguredCapacity() {
        enableImmediateRetentionCleanup()
        UserDefaults.standard.set(100, forKey: UserDefaultsKeys.historyMaxItems)
        for i in 0..<105 {
            let item = ClipboardItem(
                timestamp: Date(timeIntervalSince1970: Double(i)),
                content: "Configured \(i)",
                sourceFormat: .text
            )
            assertInserted(item)
        }

        let items = db.recent(limit: 110)
        XCTAssertEqual(items.count, 100)
        XCTAssertTrue(items.contains { $0.content == "Configured 104" })
        XCTAssertFalse(items.contains { $0.content == "Configured 0" })
    }

    /// 插入热路径应节流保留策略清理，降低高频复制时的 DELETE 查询成本。
    func testHistoryRetentionCleanupIsThrottledDuringInsert() {
        db.setRetentionCleanupIntervalForTesting(3)
        UserDefaults.standard.set(100, forKey: UserDefaultsKeys.historyMaxItems)

        for i in 0..<101 {
            assertInserted(makeItem(content: "Item \(i)", timestamp: Date(timeIntervalSince1970: Double(i))))
        }

        XCTAssertEqual(db.recent(limit: 110).count, 101)

        assertInserted(makeItem(content: "Item 101", timestamp: Date(timeIntervalSince1970: 101)))

        let items = db.recent(limit: 110)
        XCTAssertEqual(items.count, 100)
        XCTAssertEqual(items.first?.content, "Item 101")
        XCTAssertFalse(items.contains { $0.content == "Item 0" })
    }

    /// 用户设置的清理周期应删除过期非收藏记录，但保留收藏项
    func testHistoryRetentionPrunesExpiredNonPinnedItemsOnly() {
        let oldDate = Date().addingTimeInterval(-8 * 86_400)
        let old = ClipboardItem(timestamp: oldDate, content: "Expired", sourceFormat: .text)
        let oldPinned = ClipboardItem(timestamp: oldDate, content: "Expired pinned", sourceFormat: .text, isPinned: true)
        let recent = ClipboardItem(content: "Recent", sourceFormat: .text)

        assertInserted(old)
        assertInserted(oldPinned)
        assertInserted(recent)

        db.enforceHistoryRetention(policy: HistoryRetentionPolicy(maxItems: 100, maxAgeDays: 7))

        let items = db.recent(limit: 10)
        XCTAssertFalse(items.contains { $0.content == "Expired" })
        XCTAssertTrue(items.contains { $0.content == "Expired pinned" })
        XCTAssertTrue(items.contains { $0.content == "Recent" })
    }

    /// favorites(limit:) 应遵守 limit
    func testFavoritesLimit() {
        for i in 0..<10 {
            let item = makeItem(content: "Pin \(i)", pinned: true, timestamp: Date(timeIntervalSince1970: Double(i)))
            db.insert(item)
        }

        let limited = db.favorites(limit: 3)
        XCTAssertEqual(limited.count, 3)
    }

    // MARK: - rawFormatData 持久化

    /// RTF 原始格式数据写入后完整回读
    func testRawFormatDataRoundTripRTF() {
        let raw = Data([0x7B, 0x5C, 0x72, 0x74, 0x66, 0x31])  // "{\\rtf1"
        let item = ClipboardItem(
            content: "hello",
            sourceFormat: .rtf,
            rawFormatData: raw,
            rawFormatType: "public.rtf"
        )
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        let loaded = db.loadRawFormatData(id: items[0].id)
        XCTAssertEqual(loaded.data, raw)
        XCTAssertEqual(loaded.type, "public.rtf")
    }

    /// HTML 原始格式数据写入后通过按需加载回读
    func testRawFormatDataRoundTripHTML() {
        let raw = Data("<p>hello</p>".utf8)
        let item = ClipboardItem(
            content: "hello",
            sourceFormat: .html,
            rawFormatData: raw,
            rawFormatType: "public.html"
        )
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        let loaded = db.loadRawFormatData(id: items[0].id)
        XCTAssertEqual(loaded.data, raw)
        XCTAssertEqual(loaded.type, "public.html")
    }

    /// 普通条目（.text）无原始格式数据
    func testRawFormatDataNilByDefault() {
        let item = makeItem(content: "纯文本", type: .text)
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].rawFormatData)
        XCTAssertNil(items[0].rawFormatType)
    }

    // MARK: - content 截断

    /// 插入超长文本 → recent() 返回 ≤256 字符
    func testContentTruncatedOnQuery() {
        let longText = String(repeating: "超级大文本内容", count: 50) // ~450 字符
        XCTAssertGreaterThan(longText.count, 256)

        let item = makeItem(content: longText, type: .text)
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].content.count, 256)
        XCTAssertTrue(longText.hasPrefix(items[0].content))
    }

    /// FTS 搜索应覆盖完整 content，而不是只搜索列表截断的 256 字符
    func testSearchFindsContentBeyondListTruncation() {
        let prefix = String(repeating: "A", count: 300)
        let item = makeItem(content: "\(prefix) uniqueTailNeedle", type: .text)
        db.insert(item)

        let results = db.search(query: "uniqueTailNeedle")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, item.id)
    }

    /// loadFullContent 返回完整内容（未被截断）
    func testLoadFullContentReturnsFull() {
        let longText = String(repeating: "完整大文本", count: 40) // ~240 字符
        let item = ClipboardItem(content: longText, sourceFormat: .text)
        db.insert(item)

        let items = db.recent()
        let full = db.loadFullContent(id: items[0].id)
        XCTAssertEqual(full, longText)
    }

    /// 短文本不被截断（≤256 时原样返回）
    func testShortContentNotTruncated() {
        let short = "短文本"
        db.insert(makeItem(content: short))

        let items = db.recent()
        XCTAssertEqual(items[0].content, short)
    }

    /// 图片缓存清理应能读取仍被数据库引用的 image content 路径
    func testAllImageContentPathsUsesContentTypeColumn() {
        let imagePath = "/tmp/pastry-image-cache-test.png"
        db.insert(makeItem(content: imagePath, type: .image))
        db.insert(makeItem(content: "/tmp/pastry-file-test.pdf", type: .fileURL))
        db.insert(makeItem(content: "plain text", type: .text))

        let paths = db.allImageContentPaths()
        XCTAssertEqual(paths, [imagePath])
    }

    // MARK: - segmentsJSON 不解码

    /// segmentsJSON 被存储但 segments 在未访问时不解码
    func testSegmentsJSONStoredNotDecoded() {
        let segs: [ContentSegment] = [.text("A"), .image(url: "https://x.com/p.png")]
        let item = ClipboardItem(content: "text", sourceFormat: .html, segments: segs)
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        // segmentsJSON 已存储
        XCTAssertNotNil(items[0].segmentsJSON)
        // segments 按需解码后应正确
        XCTAssertEqual(items[0].segments?.count, 2)
        XCTAssertEqual(items[0].segments?[0].textValue, "A")
    }
}
