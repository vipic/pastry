import Foundation
import Cocoa
import CoreGraphics
import OSLog

/// 剪贴板实时写入后的入场动画描述（仅相关卡位移）。
struct ClipboardInsertAnimation: Equatable {
    let newID: UUID
    /// 需要向后让一格的卡片（被置顶项之前的那些；全新插入则为原可见全部）
    let shiftingIDs: Set<UUID>
    /// 置顶前在可见列表中的下标；全新插入为 0（新卡只淡入，不飞移）
    let promoteFromIndex: Int
}

// MARK: - 应用数据管理层
// 连接 ClipboardMonitor → DatabaseManager → SwiftUI
@MainActor
final class StoreManager: ObservableObject, @unchecked Sendable {

    static let shared = StoreManager()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "store")
    private let diagnosticsLog = PastryLogger(category: "store")

    // MARK: Published

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var filteredItems: [ClipboardItem] = []
    /// 实时插入/置顶的入场描述；Overlay 按卡做 offset，避免整带误移。
    @Published private(set) var insertAnimation: ClipboardInsertAnimation?

    /// 当前 pin tab
    @Published var pinTab: PinTab = .all {
        didSet {
            guard pinTab != oldValue else { return }
            if !suppressFilterDiagnostics {
                DeveloperDiagnostics.record(pinTab == .pinned ? DiagnosticsEvent.tabFavorites : DiagnosticsEvent.tabAll)
            }
            performSearchImmediate()
        }
    }

    /// 关键词搜索
    @Published var searchQuery = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            if !suppressFilterDiagnostics,
               !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DeveloperDiagnostics.record(DiagnosticsEvent.searchQuery)
            }
            // 清空搜索必须立刻恢复列表，否则会短暂出现「无历史」空状态（query 已空但 filteredItems 仍空）。
            if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                performSearchImmediate()
            } else {
                performSearch()
            }
        }
    }

    /// 类型筛选（nil = 全部，按来源格式过滤）
    @Published var typeFilter: SourceFormat? = nil {
        didSet {
            guard typeFilter != oldValue else { return }
            if !suppressFilterDiagnostics, let typeFilter {
                DeveloperDiagnostics.record(DiagnosticsEvent.filterType(typeFilter))
            }
            performSearchImmediate()
        }
    }

    /// URL 筛选（独立于类型，匹配 isURL 标签）
    @Published var urlFilter: Bool = false {
        didSet {
            guard urlFilter != oldValue else { return }
            if !suppressFilterDiagnostics, urlFilter {
                DeveloperDiagnostics.record(DiagnosticsEvent.filterURL)
            }
            performSearchImmediate()
        }
    }

    /// 来源 App 筛选（nil = 全部）
    @Published var appFilter: String? = nil {
        didSet {
            guard appFilter != oldValue else { return }
            if !suppressFilterDiagnostics, appFilter != nil {
                DeveloperDiagnostics.record(DiagnosticsEvent.filterApp)
            }
            performSearchImmediate()
        }
    }

    /// 来自其他设备的 Handoff 筛选
    @Published var handoffFilter: Bool = false {
        didSet {
            guard handoffFilter != oldValue else { return }
            if !suppressFilterDiagnostics, handoffFilter {
                DeveloperDiagnostics.record(DiagnosticsEvent.filterHandoff)
            }
            performSearchImmediate()
        }
    }

    /// 备注筛选
    @Published var noteFilter: NoteFilter = .any {
        didSet {
            guard noteFilter != oldValue else { return }
            if !suppressFilterDiagnostics, noteFilter != .any {
                DeveloperDiagnostics.record(DiagnosticsEvent.filterNote(noteFilter))
            }
            performSearchImmediate()
        }
    }

    /// 时间筛选
    @Published var timeFilter: TimeFilter = .any {
        didSet {
            guard timeFilter != oldValue else { return }
            if !suppressFilterDiagnostics, timeFilter != .any {
                DeveloperDiagnostics.record(DiagnosticsEvent.filterTime(timeFilter))
            }
            performSearchImmediate()
        }
    }

    /// 从当前数据中提取的去重 App 名称列表（供筛选 popover 使用）
    @Published private(set) var availableApps: [String] = []

    @Published private(set) var stats = ClipboardStats(totalItems: 0, todayItems: 0,
                                                         favoriteCount: 0, storageSizeKB: 0)

    /// clearFilters 批量重置时抑制逐项筛选埋点
    private var suppressFilterDiagnostics = false

    // MARK: 枚举

    enum PinTab: String, CaseIterable {
        case all    = "全部"
        case pinned = "已收藏"
    }

    enum TimeFilter: String, CaseIterable {
        case any        = "任何时间"
        case today      = "今天"
        case yesterday  = "昨天"
        case thisWeek   = "本周"
        case lastWeek   = "上周"
        case last30Days = "过去 30 天"

        var label: String {
            switch self {
            case .any:        return L10n["filter.time.any"]
            case .today:      return L10n["filter.time.today"]
            case .yesterday:  return L10n["filter.time.yesterday"]
            case .thisWeek:   return L10n["filter.time.thisWeek"]
            case .lastWeek:   return L10n["filter.time.lastWeek"]
            case .last30Days: return L10n["filter.time.last30Days"]
            }
        }

        /// 时间区间（闭开：start ≤ t < end），any 返回 nil
        var dateRange: Range<Date>? {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .any:        return nil
            case .today:
                let start = cal.startOfDay(for: now)
                let end   = cal.date(byAdding: .day, value: 1, to: start)!
                return start ..< end
            case .yesterday:
                let start = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!
                let end   = cal.startOfDay(for: now)
                return start ..< end
            case .thisWeek:
                let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                let end   = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
                return start ..< end
            case .lastWeek:
                let thisWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                let start = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!
                return start ..< thisWeekStart
            case .last30Days:
                let start = cal.date(byAdding: .day, value: -30, to: now)!
                return start ..< cal.date(byAdding: .second, value: 1, to: now)!
            }
        }
    }

    enum NoteFilter: String, CaseIterable {
        case any
        case withNote
        case withoutNote

        var label: String {
            switch self {
            case .any:         return L10n["filter.note.any"]
            case .withNote:    return L10n["filter.note.with"]
            case .withoutNote: return L10n["filter.note.without"]
            }
        }
    }

    private struct SearchFilterSnapshot {
        let query: String
        let pinTab: PinTab
        let typeFilter: SourceFormat?
        let urlFilter: Bool
        let appFilter: String?
        let handoffFilter: Bool
        let noteFilter: NoteFilter
        let dateRange: Range<Date>?
    }

    // MARK: 防抖

    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private let usesDatabaseSearch: Bool

    private init() {
        usesDatabaseSearch = true
        loadRecent()

        ClipboardMonitor.shared.onNewItem = { [weak self] item in
            self?.handleNewItem(item)
        }
    }

    /// 测试专用：直接注入剪贴板数据，不经过数据库
    init(items: [ClipboardItem]) {
        usesDatabaseSearch = false
        self.items = items
        performSearchImmediate()
        refreshAvailableApps()
    }

    // MARK: - 公开方法

    func start() {
        ClipboardMonitor.shared.start()
        refreshStats()
        // 低频定时器兜底：每 10 分钟执行一次保留策略，确保闲置期间旧数据也会按策略清理
        let retentionTimer = Timer(timeInterval: 600, repeats: true) { [weak self] _ in
            DatabaseManager.shared.enforceHistoryRetention()
            self?.refreshStats()
        }
        RunLoop.main.add(retentionTimer, forMode: .common)
        log.info("Store 启动")
        diagnosticsLog.info(
            "存储桥接层已启动",
            event: "store.started",
            metadata: ["item_count": String(items.count)]
        )
    }

    func pasteItem(_ item: ClipboardItem) async {
        // 与托盘粘贴共用权限闸门（主动弹系统授权，而非静默失败）
        guard AccessibilityPermissionChecker.shared.requestTrustedForPaste() else {
            Logger(subsystem: "com.nekutai.pastry", category: "store")
                .warning("粘贴中止：缺少辅助功能权限")
            diagnosticsLog.warning(
                "粘贴中止：缺少辅助功能权限",
                event: "store.paste.accessibility_denied"
            )
            await MainActor.run {
                NotificationCenter.default.post(name: .overlayAccessibilityDenied, object: nil)
            }
            return
        }

        let result = await PasteboardWriter.write(item, options: .storeSingle)
        guard result == .written else {
            diagnosticsLog.warning(
                "粘贴中止：没有可写入内容",
                event: "store.paste.no_writable_content",
                metadata: ["source_format": item.sourceFormat.rawValue]
            )
            return
        }

        DatabaseManager.shared.incrementDisplayCount(id: item.id.uuidString)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Self.simulatePaste()
        }
    }

    private static func simulatePaste() {
        // pasteItem 已在写入剪贴板前完成权限闸门；这里不重复执行可能阻塞的 AX 查询。
        let vKey = CGKeyCode(9)
        guard let source = CGEventSource(stateID: .privateState) else {
            Logger(subsystem: "com.nekutai.pastry", category: "store").warning("CGEventSource 创建失败 — 可能缺少辅助功能权限")
            return
        }

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return
        }

        cmdDown.flags = .maskCommand
        cmdUp.flags = .maskCommand

        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        cmdDown.postToPid(pid)
        cmdUp.postToPid(pid)
    }

    /// 切换 pin 状态
    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        DatabaseManager.shared.togglePin(id: item.id.uuidString)
        items[idx].isPinned.toggle()
        DeveloperDiagnostics.record(items[idx].isPinned ? DiagnosticsEvent.favoritePin : DiagnosticsEvent.favoriteUnpin)
        performSearchImmediate()
    }

    /// 更新链接预览标题（DB 持久化 + 内存同步）
    func updateLinkTitle(_ itemId: UUID, linkTitle: String?) {
        DatabaseManager.shared.updateLinkTitle(id: itemId.uuidString, linkTitle: linkTitle)
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[idx].linkTitle = linkTitle
        // 若正在显示筛选结果，刷新以反映变更
        if hasActiveFilters { performSearchImmediate() }
    }

    /// 更新场景备注（所有条目均可添加；空白文本会清空备注）
    func updateFavoriteNote(_ itemId: UUID, note: String?) {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = trimmed.isEmpty ? nil : trimmed
        let updatedAt = normalized == nil ? nil : Date()

        guard DatabaseManager.shared.updateFavoriteNote(
            id: itemId.uuidString,
            note: normalized,
            updatedAt: updatedAt
        ) else { return }

        guard let idx = items.firstIndex(where: { $0.id == itemId }) else {
            performSearchImmediate()
            return
        }
        items[idx].favoriteNote = normalized
        items[idx].favoriteNoteUpdatedAt = updatedAt
        performSearchImmediate()
    }

    /// 批量设置选中项的 pin 状态
    func setPinForSelected(_ ids: Set<UUID>, pinned: Bool) {
        var changed = false
        for id in ids {
            guard let idx = items.firstIndex(where: { $0.id == id }),
                  items[idx].isPinned != pinned else { continue }
            DatabaseManager.shared.setPin(id: id.uuidString, pinned: pinned)
            items[idx].isPinned = pinned
            changed = true
        }
        if changed {
            DeveloperDiagnostics.record(pinned ? DiagnosticsEvent.favoritePin : DiagnosticsEvent.favoriteUnpin)
        }
        performSearchImmediate()
    }

    /// 批量删除选中项。返回实际删除的记录 ID。收藏不豁免用户删除（仅自动保留策略跳过收藏）。
    @discardableResult
    func deleteSelected(
        _ ids: Set<UUID>,
        clearSystemClipboardWhenEmpty: Bool = true
    ) -> Set<UUID> {
        var deletedIds = Set<UUID>()
        var deletedFavorite = false

        ClipboardMonitor.shared.suspend()
        for id in ids {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            if item.isPinned { deletedFavorite = true }
            let deletedFromDatabase = !usesDatabaseSearch
                || DatabaseManager.shared.delete(id: id.uuidString)
            guard deletedFromDatabase else {
                diagnosticsLog.error(
                    "删除剪贴板记录失败，保留界面中的卡片",
                    event: "store.delete.persistence_failed",
                    metadata: ["item_id": id.uuidString]
                )
                continue
            }
            items.removeAll { $0.id == id }
            deletedIds.insert(id)
        }

        if clearSystemClipboardWhenEmpty, items.isEmpty {
            PasteboardWriter.clearSystemClipboard()
        }

        ClipboardMonitor.shared.resume()
        performSearchImmediate()
        refreshAvailableApps()

        if !deletedIds.isEmpty {
            DeveloperDiagnostics.record(DiagnosticsEvent.delete)
            if deletedFavorite {
                DeveloperDiagnostics.record(DiagnosticsEvent.deleteIncludingFavorite)
            }
        }

        return deletedIds
    }

    /// 清空全部（含 pinned）
    func clearAll() {
        ClipboardMonitor.shared.suspend()
        DatabaseManager.shared.clearAll()
        items.removeAll()
        filteredItems.removeAll()
        refreshStats()
        PasteboardWriter.clearSystemClipboard()
        ClipboardMonitor.shared.resume()
        DeveloperDiagnostics.record(DiagnosticsEvent.clearAll)
    }

    /// 是否有活跃的筛选条件
    var hasActiveFilters: Bool {
        !(searchQuery.isEmpty
            && typeFilter == nil
            && appFilter == nil
            && timeFilter == .any
            && pinTab == .all
            && !urlFilter
            && !handoffFilter
            && noteFilter == .any)
    }

    /// 清除所有筛选条件
    func clearFilters(recordDiagnostics: Bool = true) {
        let hadFilters = hasActiveFilters || !searchQuery.isEmpty
        // 已是默认态时不再写 @Published，避免打开面板时连打多次 executeSearch 卡入场动画
        guard hadFilters else { return }
        suppressFilterDiagnostics = true
        defer { suppressFilterDiagnostics = false }
        searchQuery = ""
        typeFilter = nil
        appFilter = nil
        timeFilter = .any
        pinTab = .all
        urlFilter = false
        handoffFilter = false
        noteFilter = .any
        if recordDiagnostics {
            DeveloperDiagnostics.record(DiagnosticsEvent.filterClear)
        }
    }

    func refresh() {
        loadRecent()
        refreshStats()
    }

    func applyHistoryRetentionSettings(
        enforce: () -> Void = { DatabaseManager.shared.enforceHistoryRetention() },
        reloadFromDatabase: Bool = true
    ) {
        enforce()
        guard reloadFromDatabase else { return }
        loadRecent()
        refreshStats()
    }

    // MARK: - 内部

    private func handleNewItem(_ item: ClipboardItem) {
        let result = DatabaseManager.shared.insert(item)
        var isPinned = item.isPinned
        var favoriteNote = item.favoriteNote
        var favoriteNoteUpdatedAt = item.favoriteNoteUpdatedAt
        var replacedOldID: UUID?
        switch result {
        case .skippedDuplicate, .skipped:
            return
        case .replaced(let oldID, let preservedPinned, let preservedNote, let preservedNoteAt):
            replacedOldID = UUID(uuidString: oldID)
            isPinned = preservedPinned
            favoriteNote = preservedNote
            favoriteNoteUpdatedAt = preservedNoteAt
        case .inserted:
            break
        }

        // 内存中的 items 数组截断 content 至 256 字符（DB 保留完整内容用于粘贴和 FTS）
        let truncatedContent = item.content.count > 256 ? String(item.content.prefix(256)) : item.content
        let listItem = ClipboardItem(
            id: item.id, timestamp: item.timestamp,
            content: truncatedContent, sourceFormat: item.sourceFormat, tags: item.tags,
            appName: item.appName, isHandoff: item.isHandoff,
            textAnnotation: item.textAnnotation,
            linkTitle: item.linkTitle,
            segmentsJSON: item.segmentsJSON,
            rawFormatData: item.rawFormatData, rawFormatType: item.rawFormatType,
            displayCount: item.displayCount, isPinned: isPinned,
            favoriteNote: favoriteNote,
            favoriteNoteUpdatedAt: favoriteNoteUpdatedAt
        )

        // 入场：只让「被挤到的」卡片位移；置顶项之后的卡片保持不动。
        let visibleBefore = filteredItems
        let animation: ClipboardInsertAnimation
        if let replacedOldID,
           let oldIndex = visibleBefore.firstIndex(where: { $0.id == replacedOldID }) {
            animation = ClipboardInsertAnimation(
                newID: listItem.id,
                shiftingIDs: Set(visibleBefore.prefix(oldIndex).map(\.id)),
                promoteFromIndex: oldIndex
            )
        } else {
            animation = ClipboardInsertAnimation(
                newID: listItem.id,
                shiftingIDs: Set(visibleBefore.map(\.id)),
                promoteFromIndex: 0
            )
        }

        if let replacedOldID {
            items.removeAll { $0.id == replacedOldID }
        }
        items.insert(listItem, at: 0)

        let noActiveFilters = searchQuery.isEmpty
            && typeFilter == nil
            && appFilter == nil
            && timeFilter == .any
            && !urlFilter
            && !handoffFilter
            && noteFilter == .any
            && pinTab == .all

        if noActiveFilters {
            filteredItems = items
        } else {
            performSearchImmediate()
        }

        // 新卡若因筛选不可见则不做入场
        if filteredItems.contains(where: { $0.id == listItem.id }) {
            insertAnimation = animation
            let token = listItem.id
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(UIConstants.Motion.fast * 1_200_000_000))
                if insertAnimation?.newID == token {
                    insertAnimation = nil
                }
            }
        }

        refreshStats()
        refreshAvailableApps()
    }

    private func loadRecent() {
        items = DatabaseManager.shared.recent(limit: 500)
        performSearchImmediate()
        refreshAvailableApps()
    }

    private func performSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms 防抖
            guard !Task.isCancelled else { return }
            await MainActor.run {
                executeSearch()
            }
        }
    }

    private func performSearchImmediate() {
        searchTask?.cancel()
        executeSearch()
    }

    private func executeSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        let filters = SearchFilterSnapshot(
            query: query,
            pinTab: pinTab,
            typeFilter: typeFilter,
            urlFilter: urlFilter,
            appFilter: appFilter,
            handoffFilter: handoffFilter,
            noteFilter: noteFilter,
            dateRange: timeFilter.dateRange
        )
        let recentItems = items
        searchGeneration += 1

        // 确定基础数据源：生产环境关键词搜索走 SQLite FTS，覆盖完整历史和长文本。
        let searchedInDatabase = usesDatabaseSearch && !query.isEmpty
        guard searchedInDatabase else {
            filteredItems = Self.filteredResults(
                base: recentItems,
                recentItems: recentItems,
                filters: filters,
                searchedInDatabase: false
            )
            return
        }

        let generation = searchGeneration
        searchTask?.cancel()
        let manager = self
        searchTask = Task.detached(priority: .userInitiated) { [manager] in
            guard !Task.isCancelled else { return }
            let databaseResults = DatabaseManager.shared.search(query: query, limit: 500)
            guard !Task.isCancelled else { return }
            let filteredResults = Self.filteredResults(
                base: databaseResults,
                recentItems: recentItems,
                filters: filters,
                searchedInDatabase: true
            )

            await MainActor.run {
                guard !Task.isCancelled,
                      manager.searchGeneration == generation
                else { return }
                manager.filteredItems = filteredResults
            }
        }
    }

    nonisolated private static func filteredResults(
        base initialBase: [ClipboardItem],
        recentItems: [ClipboardItem],
        filters: SearchFilterSnapshot,
        searchedInDatabase: Bool
    ) -> [ClipboardItem] {
        var base = initialBase
        if filters.pinTab == .pinned {
            base = base.filter { $0.isPinned }
        }

        // 测试注入数据和无数据库路径：content + appName 大小写不敏感子串匹配。
        if !filters.query.isEmpty && !searchedInDatabase {
            base = base.filtered(by: filters.query)
        } else if searchedInDatabase {
            // 保留旧交互：来源 App 名称也可命中。数据库 FTS 负责内容，最近内存列表补 App 名称。
            let existing = Set(base.map(\.id))
            let appMatches = recentItems.filtered(by: filters.query).filter { !existing.contains($0.id) }
            base.append(contentsOf: appMatches)
        }

        // 类型筛选（按来源格式）
        if let type = filters.typeFilter {
            base = base.filter { $0.sourceFormat == type }
        }

        // URL 筛选（独立于类型）
        if filters.urlFilter {
            base = base.filter { $0.tags.isURL }
        }

        // App 筛选
        if let app = filters.appFilter {
            base = base.filter { $0.appName == app }
        }

        // 其他设备（Handoff）筛选
        if filters.handoffFilter {
            base = base.filter { $0.isHandoff }
        }

        switch filters.noteFilter {
        case .any:
            break
        case .withNote:
            base = base.filter { item in
                !(item.favoriteNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
        case .withoutNote:
            base = base.filter { item in
                item.favoriteNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            }
        }

        // 时间筛选
        if let range = filters.dateRange {
            base = base.filter { range.contains($0.timestamp) }
        }

        return base
    }

    private func refreshAvailableApps() {
        let apps = Set(items.compactMap { $0.appName }.filter { $0 != "Finder" && $0 != "loginwindow" })
        availableApps = apps.sorted()
    }

    private func refreshStats() {
        stats = DatabaseManager.shared.stats()
    }
}
