import XCTest
@testable import Pastry

// MARK: - StoreManager 测试套件
// 测试筛选、搜索、状态管理逻辑（CRUD 由 DatabaseManagerTests 覆盖）

@MainActor
final class StoreManagerTests: XCTestCase {

    var store: StoreManager!

    override func setUp() async throws {
        // 每个测试自己创建 StoreManager
    }

    override func tearDown() async throws {
        store = nil
    }

    // MARK: - 辅助方法

    private func makeStoreWithItems(_ specs: [(content: String, type: SourceFormat, app: String?, pinned: Bool, daysAgo: Int)]) -> StoreManager {
        let cal = Calendar.current
        let now = Date()
        let items: [ClipboardItem] = specs.map { spec in
            let date = cal.date(byAdding: .day, value: -spec.daysAgo, to: now)!
            return ClipboardItem(
                timestamp: date,
                content: spec.content,
                sourceFormat: spec.type,
                appName: spec.app,
                isPinned: spec.pinned
            )
        }
        return StoreManager(items: items)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    // MARK: - PinTab 筛选

    func testPinTabAllShowsEverything() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", true, 0),
            ("B", .text, "Chrome", false, 0),
        ])

        store.pinTab = .all
        XCTAssertEqual(store.filteredItems.count, 2)
    }

    func testPinTabPinnedOnlyShowsPinned() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", true, 0),
            ("B", .text, "Chrome", false, 0),
            ("C", .text, "Xcode", true, 0),
        ])

        store.pinTab = .pinned
        XCTAssertEqual(store.filteredItems.count, 2)
        XCTAssertTrue(store.filteredItems.allSatisfy { $0.isPinned })
    }

    // MARK: - 类型筛选

    func testTypeFilterText() {
        store = makeStoreWithItems([
            ("text a", .text, "Safari", false, 0),
            ("img 1", .image, "Preview", false, 0),
            ("text b", .text, "Chrome", false, 0),
        ])

        store.typeFilter = .text
        XCTAssertEqual(store.filteredItems.count, 2)
        XCTAssertTrue(store.filteredItems.allSatisfy { $0.sourceFormat == .text })
    }

    func testTypeFilterImage() {
        store = makeStoreWithItems([
            ("text a", .text, "Safari", false, 0),
            ("img 1", .image, "Preview", false, 0),
        ])

        store.typeFilter = .image
        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].sourceFormat, .image)
    }

    func testTypeFilterNilShowsAll() {
        store = makeStoreWithItems([
            ("text a", .text, "Safari", false, 0),
            ("img 1", .image, "Preview", false, 0),
        ])

        store.typeFilter = nil
        XCTAssertEqual(store.filteredItems.count, 2)
    }

    // MARK: - App 筛选

    func testAppFilter() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 0),
            ("B", .text, "Chrome", false, 0),
            ("C", .text, "Safari", false, 0),
        ])

        store.appFilter = "Safari"
        XCTAssertEqual(store.filteredItems.count, 2)
        XCTAssertTrue(store.filteredItems.allSatisfy { $0.appName == "Safari" })
    }

    func testAppFilterNilShowsAll() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 0),
            ("B", .text, "Chrome", false, 0),
        ])

        store.appFilter = nil
        XCTAssertEqual(store.filteredItems.count, 2)
    }

    // MARK: - URL / Handoff 筛选

    func testURLFilterKeepsOnlyURLTaggedItems() {
        let items = [
            ClipboardItem(
                content: "https://example.com",
                sourceFormat: .text,
                tags: ContentTags(isURL: true),
                appName: "Safari"
            ),
            ClipboardItem(content: "plain note", sourceFormat: .text, appName: "Notes"),
            ClipboardItem(
                content: "https://other.test",
                sourceFormat: .html,
                tags: ContentTags(isURL: true),
                appName: "Chrome"
            ),
        ]
        store = StoreManager(items: items)
        store.urlFilter = true
        XCTAssertEqual(store.filteredItems.count, 2)
        XCTAssertTrue(store.filteredItems.allSatisfy { $0.tags.isURL })
    }

    func testURLFilterOffShowsAll() {
        let items = [
            ClipboardItem(
                content: "https://example.com",
                sourceFormat: .text,
                tags: ContentTags(isURL: true)
            ),
            ClipboardItem(content: "plain", sourceFormat: .text),
        ]
        store = StoreManager(items: items)
        store.urlFilter = false
        XCTAssertEqual(store.filteredItems.count, 2)
    }

    func testHandoffFilterKeepsOnlyHandoffItems() {
        let items = [
            ClipboardItem(content: "from phone", sourceFormat: .text, isHandoff: true),
            ClipboardItem(content: "local", sourceFormat: .text, isHandoff: false),
            ClipboardItem(content: "from ipad", sourceFormat: .text, isHandoff: true),
        ]
        store = StoreManager(items: items)
        store.handoffFilter = true
        XCTAssertEqual(store.filteredItems.count, 2)
        XCTAssertTrue(store.filteredItems.allSatisfy(\.isHandoff))
    }

    func testHandoffFilterOffShowsAll() {
        let items = [
            ClipboardItem(content: "from phone", sourceFormat: .text, isHandoff: true),
            ClipboardItem(content: "local", sourceFormat: .text, isHandoff: false),
        ]
        store = StoreManager(items: items)
        store.handoffFilter = false
        XCTAssertEqual(store.filteredItems.count, 2)
    }

    // MARK: - 备注筛选

    func testNoteFilterWithAndWithoutNote() {
        let items = [
            ClipboardItem(content: "meeting link", sourceFormat: .text, favoriteNote: "周会时复制"),
            ClipboardItem(content: "plain text", sourceFormat: .text),
            ClipboardItem(content: "blank note", sourceFormat: .text, favoriteNote: "   "),
        ]
        store = StoreManager(items: items)

        store.noteFilter = .withNote
        XCTAssertEqual(store.filteredItems.map(\.content), ["meeting link"])

        store.noteFilter = .withoutNote
        XCTAssertEqual(Set(store.filteredItems.map(\.content)), Set(["plain text", "blank note"]))
    }

    // MARK: - 时间筛选

    func testTimeFilterToday() {
        // "A" 是 2 天前，"B" 是今天
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 2),
            ("B", .text, "Chrome", false, 0),
        ])

        store.timeFilter = .today
        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].content, "B")
    }

    func testTimeFilterAny() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 10),
            ("B", .text, "Chrome", false, 5),
        ])

        store.timeFilter = .any
        XCTAssertEqual(store.filteredItems.count, 2)
    }

    func testTimeFilterLast30Days() {
        store = makeStoreWithItems([
            ("old", .text, "Safari", false, 35),
            ("recent", .text, "Chrome", false, 10),
            ("today", .text, "Xcode", false, 0),
        ])

        store.timeFilter = .last30Days
        XCTAssertEqual(store.filteredItems.count, 2)
        XCTAssertFalse(store.filteredItems.contains { $0.content == "old" })
    }

    // MARK: - 组合筛选

    func testCombinedFilters() {
        store = makeStoreWithItems([
            ("pinned text safari", .text, "Safari", true, 0),
            ("pinned img safari", .image, "Safari", true, 0),
            ("normal text safari", .text, "Safari", false, 0),
            ("pinned text chrome", .text, "Chrome", true, 0),
            ("pinned text safari old", .text, "Safari", true, 35),  // >30 天，应被筛掉
        ])

        store.pinTab = .pinned
        store.typeFilter = .text
        store.appFilter = "Safari"
        store.timeFilter = .last30Days

        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].content, "pinned text safari")
    }

    // MARK: - hasActiveFilters

    func testHasActiveFiltersFalseByDefault() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        XCTAssertFalse(store.hasActiveFilters)
    }

    func testHasActiveFiltersWhenSearchSet() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.searchQuery = "A"
        XCTAssertTrue(store.hasActiveFilters)
    }

    /// 无结果搜索清空后，应立刻恢复列表，不能等防抖（否则会闪「无历史」空状态）。
    func testClearingSearchQueryRestoresItemsImmediately() async throws {
        store = makeStoreWithItems([
            ("hello", .text, nil, false, 0),
            ("world", .text, nil, false, 0),
        ])
        store.searchQuery = "nomatch-zzzz"
        let searchCompleted = try await waitUntil { store.filteredItems.isEmpty }
        XCTAssertTrue(searchCompleted, "无匹配搜索应在超时前完成")

        store.searchQuery = ""
        XCTAssertEqual(store.filteredItems.count, 2, "清空搜索应同步恢复，不应仍为空")
        XCTAssertFalse(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: store.searchQuery,
                typeFilter: store.typeFilter,
                appFilter: store.appFilter,
                timeFilter: store.timeFilter,
                urlFilter: store.urlFilter,
                handoffFilter: store.handoffFilter
            )
        )
    }

    func testHasActiveFiltersWhenTypeSet() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.typeFilter = .image
        XCTAssertTrue(store.hasActiveFilters)
    }

    func testHasActiveFiltersWhenPinTabPinned() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.pinTab = .pinned
        XCTAssertTrue(store.hasActiveFilters)
    }

    func testHasActiveFiltersWhenAppSet() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.appFilter = "Safari"
        XCTAssertTrue(store.hasActiveFilters)
    }

    func testHasActiveFiltersWhenTimeSet() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.timeFilter = .today
        XCTAssertTrue(store.hasActiveFilters)
    }

    func testHasActiveFiltersWhenURLFilterOn() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.urlFilter = true
        XCTAssertTrue(store.hasActiveFilters)
    }

    func testHasActiveFiltersWhenHandoffFilterOn() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.handoffFilter = true
        XCTAssertTrue(store.hasActiveFilters)
    }

    func testHasActiveFiltersWhenNoteFilterSet() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.noteFilter = .withNote
        XCTAssertTrue(store.hasActiveFilters)
    }

    // MARK: - clearFilters

    func testClearFiltersResetsAll() {
        store = makeStoreWithItems([("A", .text, "Safari", false, 0)])
        store.searchQuery = "A"
        store.typeFilter = .text
        store.appFilter = "Safari"
        store.timeFilter = .today
        store.pinTab = .pinned
        store.urlFilter = true
        store.handoffFilter = true
        store.noteFilter = .withoutNote

        store.clearFilters()

        XCTAssertEqual(store.searchQuery, "")
        XCTAssertNil(store.typeFilter)
        XCTAssertNil(store.appFilter)
        XCTAssertEqual(store.timeFilter, .any)
        XCTAssertEqual(store.pinTab, .all)
        XCTAssertFalse(store.urlFilter)
        XCTAssertFalse(store.handoffFilter)
        XCTAssertEqual(store.noteFilter, .any)
        XCTAssertFalse(store.hasActiveFilters)
    }

    func testClearFiltersNoOpWhenAlreadyClearDoesNotReselect() {
        store = makeStoreWithItems([("A", .text, "Safari", false, 0)])
        let before = store.filteredItems.map(\.id)
        store.clearFilters()
        XCTAssertEqual(store.filteredItems.map(\.id), before)
        store.clearFilters()
        XCTAssertEqual(store.filteredItems.map(\.id), before)
    }

    // MARK: - History Retention

    func testApplyHistoryRetentionSettingsInvokesCleanup() {
        store = makeStoreWithItems([("A", .text, "Safari", false, 0)])
        var didEnforce = false

        store.applyHistoryRetentionSettings(
            enforce: { didEnforce = true },
            reloadFromDatabase: false
        )

        XCTAssertTrue(didEnforce)
    }

    // MARK: - togglePin

    func testTogglePinInMemory() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 0),
        ])
        let item = store.filteredItems[0]

        _ = store.togglePin(item)

        // 注意：togglePin 会调用 DatabaseManager.shared.togglePin
        // 在测试环境这里会失败（无真实 DB），但内存状态应更新
        XCTAssertTrue(store.filteredItems[0].isPinned)
    }

    func testTogglePinUnpinInMemory() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", true, 0),
        ])
        let item = store.filteredItems[0]

        _ = store.togglePin(item)

        XCTAssertFalse(store.filteredItems[0].isPinned)
    }

    func testTogglePinPersistenceFailureKeepsStateAndReturnsFailure() {
        let item = ClipboardItem(content: "A", sourceFormat: .text, isPinned: false)
        store = StoreManager(items: [item], togglePinPersistence: { _ in false })

        XCTAssertFalse(store.togglePin(item))
        XCTAssertFalse(store.filteredItems[0].isPinned)
    }

    func testBatchPinReportsPartialFailureAndKeepsCompletedChanges() {
        let first = ClipboardItem(content: "A", sourceFormat: .text, isPinned: false)
        let second = ClipboardItem(content: "B", sourceFormat: .text, isPinned: false)
        store = StoreManager(
            items: [first, second],
            setPinPersistence: { id, _ in id == first.id }
        )

        let result = store.setPinForSelected([first.id, second.id], pinned: true)

        XCTAssertEqual(result, .init(requested: 2, completed: 1, failed: 1))
        XCTAssertTrue(store.items.first(where: { $0.id == first.id })!.isPinned)
        XCTAssertFalse(store.items.first(where: { $0.id == second.id })!.isPinned)
    }

    func testClearFailureKeepsItemsAndDoesNotClearInjectedClipboard() {
        let item = ClipboardItem(content: "A", sourceFormat: .text)
        var clipboardClearCount = 0
        store = StoreManager(
            items: [item],
            clearAllPersistence: { false },
            clearClipboard: { clipboardClearCount += 1 }
        )

        XCTAssertFalse(store.clearAll())
        XCTAssertEqual(store.items.map(\.id), [item.id])
        XCTAssertEqual(clipboardClearCount, 0)
    }

    func testClearSuccessUsesOnlyInjectedClipboard() {
        let item = ClipboardItem(content: "A", sourceFormat: .text)
        var clipboardClearCount = 0
        store = StoreManager(
            items: [item],
            clearAllPersistence: { true },
            clearClipboard: { clipboardClearCount += 1 }
        )

        XCTAssertTrue(store.clearAll())
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(clipboardClearCount, 1)
    }

    // MARK: - deleteSelected

    func testDeleteSelectedRemovesPinnedByDefault() {
        store = makeStoreWithItems([
            ("pinned", .text, "Safari", true, 0),
            ("normal", .text, "Chrome", false, 0),
        ])

        let ids = Set(store.filteredItems.map { $0.id })
        let deletedIds = store.deleteSelected(ids)

        XCTAssertEqual(deletedIds, ids)
        XCTAssertTrue(store.filteredItems.isEmpty)
    }

    func testDeleteSelectedRemovesMultiple() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 0),
            ("B", .text, "Chrome", false, 0),
            ("C", .text, "Xcode", false, 0),
        ])

        let ids = Set(store.filteredItems.prefix(2).map { $0.id })
        let deletedIds = store.deleteSelected(ids)

        XCTAssertEqual(deletedIds, ids)
        XCTAssertEqual(store.filteredItems.count, 1)
    }

    // MARK: - dedupKey 含 textAnnotation

    func testDedupKeyIncludesTextAnnotation() {
        let a = ClipboardItem(content: "/tmp/img.png", sourceFormat: .image, textAnnotation: "hello")
        let b = ClipboardItem(content: "/tmp/img.png", sourceFormat: .image, textAnnotation: "world")
        // 不同附注 → 不同 dedupKey
        XCTAssertNotEqual(a.dedupKey, b.dedupKey)
    }

    func testDedupKeySameWhenAnnotationSame() {
        let a = ClipboardItem(content: "/tmp/img.png", sourceFormat: .image, textAnnotation: "same")
        let b = ClipboardItem(content: "/tmp/img.png", sourceFormat: .image, textAnnotation: "same")
        XCTAssertEqual(a.dedupKey, b.dedupKey)
    }

    func testDedupKeyNilAnnotation() {
        let a = ClipboardItem(content: "/tmp/img.png", sourceFormat: .image)
        let b = ClipboardItem(content: "/tmp/img.png", sourceFormat: .image, textAnnotation: "has text")
        XCTAssertNotEqual(a.dedupKey, b.dedupKey)
    }

    func testDedupKeySeparatesTextAndFileURL() {
        let text = ClipboardItem(content: "/tmp/demo.txt", sourceFormat: .text)
        let file = ClipboardItem(content: "/tmp/demo.txt", sourceFormat: .fileURL)

        XCTAssertNotEqual(text.dedupKey, file.dedupKey)
    }

    func testDedupKeySeparatesFileURLAndImage() {
        let file = ClipboardItem(content: "/tmp/demo.png", sourceFormat: .fileURL)
        let image = ClipboardItem(content: "/tmp/demo.png", sourceFormat: .image)

        XCTAssertNotEqual(file.dedupKey, image.dedupKey)
    }

    // MARK: - dedupKey 含 segments

    func testDedupKeyIncludesSegments() {
        let a = ClipboardItem(content: "text", sourceFormat: .html, segments: [
            .image(url: "https://a.com/1.png"), .text("文字")
        ])
        let b = ClipboardItem(content: "text", sourceFormat: .html, segments: [
            .image(url: "https://a.com/2.png"), .text("文字")
        ])
        // 不同图片 URL → 不同 dedupKey
        XCTAssertNotEqual(a.dedupKey, b.dedupKey)
    }

    func testDedupKeySameSegmentsSame() {
        let segs: [ContentSegment] = [.text("A"), .image(url: "https://a.com/pic.png")]
        let a = ClipboardItem(content: "A", sourceFormat: .html, segments: segs)
        let b = ClipboardItem(content: "A", sourceFormat: .html, segments: segs)
        XCTAssertEqual(a.dedupKey, b.dedupKey)
    }

    func testDedupKeySegmentsNilVsSome() {
        let a = ClipboardItem(content: "text", sourceFormat: .html, segments: nil)
        let b = ClipboardItem(content: "text", sourceFormat: .html, segments: [.text("text")])
        XCTAssertNotEqual(a.dedupKey, b.dedupKey)
    }

    // MARK: - availableApps

    func testAvailableAppsDedupedAndSorted() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 0),
            ("B", .text, "Chrome", false, 0),
            ("C", .text, "Safari", false, 0),
            ("D", .text, "Xcode", false, 0),
        ])

        XCTAssertEqual(store.availableApps, ["Chrome", "Safari", "Xcode"])
    }

    func testAvailableAppsExcludesFinder() {
        store = makeStoreWithItems([
            ("A", .text, "Finder", false, 0),
            ("B", .text, "Safari", false, 0),
        ])

        XCTAssertEqual(store.availableApps, ["Safari"])
    }

    func testAvailableAppsExcludesLoginwindow() {
        store = makeStoreWithItems([
            ("A", .text, "loginwindow", false, 0),
            ("B", .text, "Safari", false, 0),
        ])

        XCTAssertEqual(store.availableApps, ["Safari"])
    }

    func testAvailableAppsHandlesNilApp() {
        store = makeStoreWithItems([
            ("A", .text, nil, false, 0),
            ("B", .text, "Safari", false, 0),
        ])

        XCTAssertEqual(store.availableApps, ["Safari"])
    }

    // MARK: - 时间区间筛选（双向范围）

    func testYesterdayExcludesToday() {
        // yesterday: 1 天前；today: 0 天前 → yesterday 不应包含 today
        store = makeStoreWithItems([
            ("A", .text, nil, false, 1),
            ("B", .text, nil, false, 0),
        ])
        store.timeFilter = .yesterday
        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].content, "A")
    }

    func testYesterdayExcludesTwoDaysAgo() {
        store = makeStoreWithItems([
            ("A", .text, nil, false, 2),
            ("B", .text, nil, false, 1),
        ])
        store.timeFilter = .yesterday
        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].content, "B")
    }

    func testThisWeekRange() {
        let cal = Calendar.current
        let todayWeekday = cal.component(.weekday, from: Date())
        // 本周一 = daysAgo = todayWeekday - 2 (假设周一=2)
        let daysSinceMonday = (todayWeekday - cal.firstWeekday + 7) % 7
        let lastMondayOffset = daysSinceMonday + 7

        store = makeStoreWithItems([
            ("A", .text, nil, false, daysSinceMonday),          // 本周一
            ("B", .text, nil, false, lastMondayOffset + 3),     // 上周
        ])
        store.timeFilter = .thisWeek
        XCTAssertTrue(store.filteredItems.contains { $0.content == "A" })
        XCTAssertFalse(store.filteredItems.contains { $0.content == "B" })
    }

    func testLastWeekExcludesThisWeek() {
        let cal = Calendar.current
        let todayWeekday = cal.component(.weekday, from: Date())
        let daysSinceMonday = (todayWeekday - cal.firstWeekday + 7) % 7
        let lastMondayOffset = daysSinceMonday + 7

        store = makeStoreWithItems([
            ("A", .text, nil, false, lastMondayOffset),         // 上周一
            ("B", .text, nil, false, daysSinceMonday),          // 本周一
        ])
        store.timeFilter = .lastWeek
        XCTAssertTrue(store.filteredItems.contains { $0.content == "A" })
        XCTAssertFalse(store.filteredItems.contains { $0.content == "B" })
    }

    func testTodayExcludesYesterday() {
        store = makeStoreWithItems([
            ("A", .text, nil, false, 1),
            ("B", .text, nil, false, 0),
        ])
        store.timeFilter = .today
        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].content, "B")
    }

    func testLast30DaysIncludesNow() {
        store = makeStoreWithItems([
            ("A", .text, nil, false, 0),    // now
            ("B", .text, nil, false, 10),   // 10 天前
            ("C", .text, nil, false, 35),   // 35 天前
        ])
        store.timeFilter = .last30Days
        XCTAssertEqual(store.filteredItems.count, 2)
        XCTAssertTrue(store.filteredItems.contains { $0.content == "A" })
        XCTAssertTrue(store.filteredItems.contains { $0.content == "B" })
        XCTAssertFalse(store.filteredItems.contains { $0.content == "C" })
    }

    // MARK: - TimeFilter.label 本地化覆盖

    /// 所有时间筛选项都有非空标签
    func testTimeFilterAllLabelsNonEmpty() {
        for tf in StoreManager.TimeFilter.allCases {
            XCTAssertFalse(
                tf.label.isEmpty,
                "TimeFilter.\(tf) 的标签不应为空"
            )
        }
    }

    /// 所有时间筛选项标签互不相同
    func testTimeFilterLabelsAreUnique() {
        let labels = Set(StoreManager.TimeFilter.allCases.map { $0.label })
        XCTAssertEqual(
            labels.count,
            StoreManager.TimeFilter.allCases.count,
            "每个时间筛选项的标签应唯一"
        )
    }
}
