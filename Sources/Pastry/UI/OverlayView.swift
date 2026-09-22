import SwiftUI
import AppKit

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Badge {
        static let capsuleHeight: CGFloat = 18
        static let capsuleHorizontalPadding: CGFloat = 6
        static let indicatorDotOffset: CGFloat = 3
        static let indicatorDotSize: CGFloat = 7
    }
    enum Control {
        static let inlineActionSize: CGFloat = 16
        static let statusPopoverWidth: CGFloat = 320
    }
    enum Keycap {
        static let shadowOpacity: Double = 0.18
        static let shadowY: CGFloat = 1
    }
    enum Overlay {
        static let animationDuration = UIConstants.Motion.medium
        static let dockingDragScale: CGFloat = 0.985
        static let bottomInset: CGFloat = 12
        static let compactCardMaxWidth: CGFloat = 400
        static let compactListMaxWidth: CGFloat = 520
        static let emptyStateMaxWidth: CGFloat = 330
        static let emptyStateMinHeight: CGFloat = UIConstants.Card.size + bottomInset
        static let emptyStateVerticalPadding: CGFloat = 24
        static let horizontalPadding: CGFloat = 28
        static let insertIndicatorHeightHidden: CGFloat = 24
        static let insertIndicatorHeightVisible: CGFloat = 40
        static let insertIndicatorWidth: CGFloat = 2.5
        static let searchExpandedWidth: CGFloat = 430
        static let searchFieldWellOpacity: Double = 0.28
        static let searchTrailingPadding: CGFloat = 6
        static let toolbarButtonSize: CGFloat = 32
        static let trayContentMinHeight: CGFloat = 262  // 240 card + paddings
        static let trayCornerRadius: CGFloat = UIConstants.Radius.tray
        static let trayHorizontalPadding: CGFloat = 12
        static let sideInset: CGFloat = 12
        static let sideSearchExpandedWidth: CGFloat = 200
        static let sideUtilityControlsSpacing: CGFloat = 4
        /// 24 pt 托盘圆角与 10 pt 工具按钮圆角同心所需的边缘 inset。
        static let sideHeaderControlInset: CGFloat = 14
        static var sideHeaderHorizontalPadding: CGFloat {
            sideHeaderControlInset - sideInset
        }
        static var compactSideSearchExpandedWidth: CGFloat {
            TrayPanelLayout.sideTrayWidth
                - trayHorizontalPadding * 2
                - sideHeaderHorizontalPadding * 2
                - toolbarButtonSize * 2
                - sideUtilityControlsSpacing
                - searchTrailingPadding
        }
        static var regularCardInsertPushDistance: CGFloat {
            UIConstants.Card.size + UIConstants.Overlay.cardSpacing
        }
        static var compactRowInsertPushDistance: CGFloat {
            UIConstants.Overlay.compactRowHeight + UIConstants.Overlay.cardSpacing
        }
    }
}
enum TrayPlacement: String, CaseIterable, Identifiable {
    case bottom
    case left
    case right

    var id: String { rawValue }

    static let `default` = TrayPlacement.bottom

    static func resolved(stored: String?) -> TrayPlacement {
        guard let stored, let placement = TrayPlacement(rawValue: stored) else {
            return .default
        }
        return placement
    }

    var isSide: Bool {
        self != .bottom
    }

    func usesHorizontalCards(screenWidth: CGFloat) -> Bool {
        self == .bottom && screenWidth > 1_200
    }
}

enum TrayPlacementPreferences {
    private static let legacyPlacementKey = "tray_placement"
    private static let legacyPlacementModeKey = "tray_placement_mode"

    static func migrateLegacyPreference(defaults: UserDefaults = .standard) {
        let legacyMode = defaults.string(forKey: legacyPlacementModeKey)
        if legacyMode == "fixedBottom" {
            remember(.bottom, defaults: defaults)
        } else if defaults.object(forKey: UserDefaultsKeys.trayRememberedPlacement) == nil,
                  let legacyRaw = defaults.string(forKey: legacyPlacementKey) {
            remember(TrayPlacement.resolved(stored: legacyRaw), defaults: defaults)
        }

        defaults.removeObject(forKey: legacyPlacementKey)
        defaults.removeObject(forKey: legacyPlacementModeKey)
    }

    static func rememberedPlacement(defaults: UserDefaults = .standard) -> TrayPlacement {
        TrayPlacement.resolved(
            stored: defaults.string(forKey: UserDefaultsKeys.trayRememberedPlacement)
        )
    }

    static func effectivePlacement(defaults: UserDefaults = .standard) -> TrayPlacement {
        rememberedPlacement(defaults: defaults)
    }

    static func remember(_ placement: TrayPlacement, defaults: UserDefaults = .standard) {
        defaults.set(placement.rawValue, forKey: UserDefaultsKeys.trayRememberedPlacement)
    }
}

enum TrayPanelLayout {
    static let sideTrayWidth: CGFloat = 272
    static let sideInset: CGFloat = 12
    static let bottomHeight: CGFloat = 336

    static func panelFrame(
        for placement: TrayPlacement,
        in screenFrame: NSRect
    ) -> NSRect {
        switch placement {
        case .bottom:
            return NSRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: screenFrame.width,
                height: min(bottomHeight, screenFrame.height)
            )
        case .left:
            return NSRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: min(sideTrayWidth + sideInset * 2, screenFrame.width),
                height: screenFrame.height
            )
        case .right:
            let width = min(sideTrayWidth + sideInset * 2, screenFrame.width)
            return NSRect(
                x: screenFrame.maxX - width,
                y: screenFrame.minY,
                width: width,
                height: screenFrame.height
            )
        }
    }

    static func dockingPlacement(
        at point: NSPoint,
        in screenFrame: NSRect
    ) -> TrayPlacement? {
        // The Dock can reserve space below visibleFrame. Treat that physical
        // screen strip as the bottom edge instead of dropping the drag target.
        if point.y <= screenFrame.minY,
           point.x >= screenFrame.minX,
           point.x <= screenFrame.maxX {
            return .bottom
        }

        let candidates: [(placement: TrayPlacement, distance: CGFloat)] = [
            (.left, abs(point.x - screenFrame.minX)),
            (.right, abs(screenFrame.maxX - point.x)),
            (.bottom, abs(point.y - screenFrame.minY))
        ].filter {
            panelFrame(for: $0.placement, in: screenFrame).contains(point)
        }
        return candidates.min(by: { $0.distance < $1.distance })?.placement
    }
}

// MARK: - 通知
extension Notification.Name {
    static let overlayRequestDismiss  = Notification.Name("overlayRequestDismiss")
    static let overlayWillShow       = Notification.Name("overlayWillShow")
    static let overlayDidHide        = Notification.Name("overlayDidHide")
    static let overlaySelectAll      = Notification.Name("overlaySelectAll")
    static let overlayDeleteSelected = Notification.Name("overlayDeleteSelected")
    static let overlayAlertActive    = Notification.Name("overlayAlertActive")
    static let overlayCloseSearch    = Notification.Name("overlayCloseSearch")
    static let overlayCloseFilter    = Notification.Name("overlayCloseFilter")
    static let overlayOpenSearch     = Notification.Name("overlayOpenSearch")
    static let overlayOpenSearchImmediate = Notification.Name("overlayOpenSearchImmediate")
    static let overlayMoveUp         = Notification.Name("overlayMoveUp")
    static let overlayMoveDown       = Notification.Name("overlayMoveDown")
    static let overlayMoveLeft       = Notification.Name("overlayMoveLeft")
    static let overlayMoveRight      = Notification.Name("overlayMoveRight")
    static let overlayMoveHome       = Notification.Name("overlayMoveHome")
    static let overlayMoveEnd        = Notification.Name("overlayMoveEnd")
    static let overlayMovePageUp     = Notification.Name("overlayMovePageUp")
    static let overlayMovePageDown   = Notification.Name("overlayMovePageDown")
    static let overlayMoveCursor     = Notification.Name("overlayMoveCursor")
    static let overlayConfirmPaste   = Notification.Name("overlayConfirmPaste")
    static let overlayAlertCancel    = Notification.Name("overlayAlertCancel")
    static let overlayCmdPaste       = Notification.Name("overlayCmdPaste")
    static let overlayCmdStateChanged = Notification.Name("overlayCmdStateChanged")
    static let overlaySearchEnterPaste = Notification.Name("overlaySearchEnterPaste")
    static let overlayFocusCards = Notification.Name("overlayFocusCards")
    static let overlayCancelFavoriteNoteEditing = Notification.Name("overlayCancelFavoriteNoteEditing")
    /// Space：预览光标项（userInfo["id"]: UUID）
    static let overlayPreviewCursor = Notification.Name("overlayPreviewCursor")
    /// ⌘C：复制当前选中（不关闭面板）
    static let overlayCopySelected = Notification.Name("overlayCopySelected")
    /// ⌘P：切换选中条目收藏
    static let overlayToggleFavorite = Notification.Name("overlayToggleFavorite")
    /// 粘贴因缺少辅助功能权限被中止 — 刷新托盘 banner
    static let overlayAccessibilityDenied = Notification.Name("overlayAccessibilityDenied")
    /// userInfo["delta"]: CGFloat — 横向卡带滚动位移（侧轮微调；普通滚轮快速浏览）
    static let overlayCardStripScroll = Notification.Name("overlayCardStripScroll")
    static let overlayPlacementChanged = Notification.Name("overlayPlacementChanged")
    static let overlayDockingDragChanged = Notification.Name("overlayDockingDragChanged")
}

// MARK: - 覆盖层主视图
struct OverlayView: View {

    /// 启动预热时为 true：只建视图树做首帧布局，不装监听、不播入场动画。
    var isPipelineWarmup: Bool = false

    @EnvironmentObject private var store: StoreManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(UserDefaultsKeys.appleIntelligenceEnabled)
    private var appleIntelligenceEnabled = false

    @State private var trayPlacement = TrayPlacementPreferences.effectivePlacement()
    @State private var isTrayPinned = false
    @State private var cardVisible = false
    @State private var isDockingDragActive = false
    @State private var selection = SelectionState()
    @State private var renderedIds: Set<UUID> = []    // 当前已渲染（可见）的卡片 ID
    @State private var commandShortcutIds: [UUID] = []
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteIds: Set<UUID> = []
    /// 右键删除不主动清剪贴板；键盘 / 工具栏批量删除在历史变空时同步清空。
    @State private var pendingClearClipboardWhenEmpty = true
    @State private var showSearch = false
    @State private var showFilterPopover = false
    @State private var showNaturalLanguageSearchStatus = false
    @State private var hoverSearch = false
    @State private var hoverClearSearch = false
    @State private var hoverFilter = false
    @State private var hoverGear = false
    @State private var hoverPin = false
    @State private var hoverMultiAction: MultiSelectToolbarAction? = nil
    @State private var hoverTab: StoreManager.PinTab? = nil
    @State private var cmdDown = false
    @FocusState private var isSearchFocused: Bool
    @StateObject private var keyHandler = KeyboardEventHandler()
    @State private var iconPrefetchTask: Task<Void, Never>?

    /// 滚到尽头时的边缘光晕（不移动卡片，避免抖动/内缩）
    @State private var stripEdgeGlow: StripEdgeSide? = nil
    @State private var stripEdgeGlowClearTask: Task<Void, Never>?
    @State private var lastStripEdgeHapticAt: CFAbsoluteTime = 0
    /// 横向卡带与侧边列表的声明式滚动位置；不依赖私有 NSScrollView 层级。
    @State private var stripScrollPosition = ScrollPosition(idType: UUID.self, edge: .leading)
    @State private var sideScrollPosition = ScrollPosition(idType: UUID.self, edge: .top)
    @State private var stripScrollGeometry = StripScrollGeometry.zero
    /// 辅助功能权限（托盘顶部非阻断 banner）
    @State private var accessibilityTrusted = true
    @State private var persistenceErrorMessage: String?
    @State private var retryPersistenceAction: (() -> Void)?

    private enum StripEdgeSide {
        case leading
        case trailing
    }

    private struct StripScrollGeometry: Equatable {
        var offsetX: CGFloat
        var maxOffsetX: CGFloat

        static let zero = StripScrollGeometry(offsetX: 0, maxOffsetX: 0)
    }

    private enum MultiSelectToolbarAction {
        case paste
        case copy
        case smart
        case delete
    }

    // MARK: - Body

    var body: some View {
        // Split lifecycle into two `some View` helpers instead of dual AnyView type-erasure.
        attachAlertAndSearchLifecycle(attachCoreLifecycle(overlayContent))
    }

    private var overlayContent: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            positionedCardContainer
                .opacity(cardVisible ? 1 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: UIConstants.Motion.medium), value: showSearch)

            if showDeleteConfirm {
                deleteConfirmOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.root)
    }

    @ViewBuilder
    private var positionedCardContainer: some View {
        switch trayPlacement {
        case .bottom:
            VStack(spacing: 0) {
                Spacer()
                cardContainer
                    .scaleEffect(isDockingDragActive ? Local.Overlay.dockingDragScale : 1, anchor: .bottom)
                    .animation(dockingDragAnimation, value: isDockingDragActive)
                    .padding(.horizontal, Local.Overlay.horizontalPadding)
                    .padding(.bottom, Local.Overlay.bottomInset)
            }
            .offset(y: cardVisible ? 0 : 200)
        case .left:
            cardContainer
                .frame(width: TrayPanelLayout.sideTrayWidth)
                .scaleEffect(isDockingDragActive ? Local.Overlay.dockingDragScale : 1, anchor: .leading)
                .animation(dockingDragAnimation, value: isDockingDragActive)
                .padding(.vertical, Local.Overlay.sideInset)
                .padding(.leading, Local.Overlay.sideInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .offset(x: cardVisible ? 0 : -200)
        case .right:
            cardContainer
                .frame(width: TrayPanelLayout.sideTrayWidth)
                .scaleEffect(isDockingDragActive ? Local.Overlay.dockingDragScale : 1, anchor: .trailing)
                .animation(dockingDragAnimation, value: isDockingDragActive)
                .padding(.vertical, Local.Overlay.sideInset)
                .padding(.trailing, Local.Overlay.sideInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: cardVisible ? 0 : 200)
        }
    }

    private var dockingDragAnimation: Animation? {
        reduceMotion
            ? nil
            : .spring(response: UIConstants.Motion.fast, dampingFraction: UIConstants.Motion.damping)
    }


    private func attachCoreLifecycle<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                guard !isPipelineWarmup else {
                    // 预热：直接落到可见态，强制 LazyHStack / 玻璃材质走完首帧布局
                    cardVisible = true
                    return
                }
                prepareForPresentation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayWillShow)) { _ in
                guard !isPipelineWarmup else { return }
                prepareForPresentation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayPlacementChanged)) { note in
                guard let rawValue = note.userInfo?["placement"] as? String,
                      let placement = TrayPlacement(rawValue: rawValue)
                else { return }
                trayPlacement = placement
                updateLayoutForCurrentScreen()
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayDockingDragChanged)) { note in
                isDockingDragActive = (note.userInfo?["active"] as? Bool) ?? false
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayDidHide)) { _ in
                guard !isPipelineWarmup else { return }
                tearDownAfterHide()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refreshAccessibilityPermission()
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayAccessibilityDenied)) { _ in
                refreshAccessibilityPermission()
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayRequestDismiss)) { _ in
                dismiss()
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayCloseSearch)) { _ in
                closeSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayCloseFilter)) { _ in
                showFilterPopover = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayOpenSearch)) { _ in
                withAnimation(searchExpansionAnimation) { showSearch = true }
                DeveloperDiagnostics.record(DiagnosticsEvent.searchOpen)
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayOpenSearchImmediate)) { _ in
                withAnimation(searchExpansionAnimation) { showSearch = true }
                DeveloperDiagnostics.record(DiagnosticsEvent.searchOpen)
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlaySelectAll)) { _ in
                let ids = Set(visibleItems.map { $0.id })
                withAnimation(.easeInOut(duration: UIConstants.Motion.instant)) { selection.selectedIds = ids }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                updateLayoutForCurrentScreen()
            }
            // 可见列表 ID 变化（删除 / 搜索 / 筛选 / 新条目）→ 默认选中第一张
            .onChange(of: store.filteredItems.map(\.id)) { oldIds, newIds in
                guard OverlayInteractionModel.shouldReselectFirstAfterVisibleIdsChange(
                    oldIds: oldIds, newIds: newIds
                ) else { return }
                selectFirstVisibleCard()
            }
            .onReceive(store.$items) { _ in
                prefetchAvailableAppIcons()
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayMoveCursor)) { note in
                handleCursorMove(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayConfirmPaste)) { _ in
                handleConfirmPaste()
            }
    }

    private func attachAlertAndSearchLifecycle<Content: View>(_ content: Content) -> some View {
        content
            .alert("收藏未保存", isPresented: Binding(
                get: { persistenceErrorMessage != nil },
                set: { if !$0 { persistenceErrorMessage = nil } }
            )) {
                Button("重试") { retryPersistenceAction?() }
                Button("取消", role: .cancel) {
                    persistenceErrorMessage = nil
                    retryPersistenceAction = nil
                }
            } message: {
                Text(persistenceErrorMessage ?? "")
            }
            .onChange(of: persistenceErrorMessage) {
                NotificationCenter.default.post(
                    name: .overlayAlertActive,
                    object: nil,
                    userInfo: ["active": persistenceErrorMessage != nil]
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayDeleteSelected)) { _ in
                handleDeleteSelectedRequest()
            }
            .onChange(of: showDeleteConfirm) {
                NotificationCenter.default.post(
                    name: .overlayAlertActive,
                    object: nil,
                    userInfo: ["active": showDeleteConfirm]
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayAlertCancel)) { _ in
                cancelDeleteConfirm()
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayCmdStateChanged)) { note in
                cmdDown = (note.userInfo?["cmdDown"] as? Bool) ?? false
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayCmdPaste)) { note in
                handleCommandPaste(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlaySearchEnterPaste)) { _ in
                handleSearchEnterPaste()
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayFocusCards)) { _ in
                guard showSearch else { return }
                isSearchFocused = false
                OverlayPanelManager.shared.keyboardOwner = .overlayNavigation
                if selection.selectedIds.isEmpty {
                    selectFirstVisibleCard()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayPreviewCursor)) { _ in
                handlePreviewCursor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayCopySelected)) { _ in
                handleCopySelected()
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayToggleFavorite)) { _ in
                handleToggleFavorite()
            }
            .onChange(of: showSearch) { onShowSearchChanged() }
            .onChange(of: showFilterPopover) { _, isPresented in
                OverlayPanelManager.shared.isFilterPopoverActive = isPresented
            }
            .onChange(of: isSearchFocused) { _, focused in
                OverlayPanelManager.shared.keyboardOwner = focused ? .searchField : .overlayNavigation
            }
    }

    private func onShowSearchChanged() {
        OverlayPanelManager.shared.isSearchActive = showSearch
        if showSearch {
            // 展开空搜索只切换输入状态；保持当前选择与卡片滚动位置。
            OverlayPanelManager.shared.keyboardOwner = .searchField
            focusSearchFieldAfterExpansion()
        } else {
            isSearchFocused = false
            showFilterPopover = false
            OverlayPanelManager.shared.keyboardOwner = .overlayNavigation
            // 搜索关键字由 closeSearch() 清除；结构化筛选保持不变。
            // 查询导致的结果变化会由 filteredItems 监听统一重置选择与滚动。
        }
    }

    private func focusSearchFieldAfterExpansion() {
        DispatchQueue.main.asyncAfter(deadline: .now() + UIConstants.Motion.medium) {
            guard showSearch else { return }
            isSearchFocused = true
        }
    }

    private func handleConfirmPaste() {
        if showDeleteConfirm {
            confirmDeleteSelected()
            return
        }
        let ids = selection.selectedIds
        guard !ids.isEmpty else {
            SoundFeedback.invalidAction()
            return
        }
        let selected = OverlayInteractionModel.selectedItems(
            visibleItems: visibleItems,
            selectedIds: ids
        )
        if selected.count == 1 {
            Task { await OverlayPanelManager.shared.hideAndPaste(selected[0]) }
        } else {
            OverlayPanelManager.shared.hideAndPasteMultiple(selected)
        }
    }

    private func handleDeleteSelectedRequest() {
        if showDeleteConfirm {
            return
        }
        guard !selection.selectedIds.isEmpty else {
            SoundFeedback.invalidAction()
            return
        }
        requestDelete(ids: selection.selectedIds)
    }

    /// 复制选中：写回系统剪贴板，不关闭面板、不触发粘贴。
    private func handleCopySelected() {
        guard !showDeleteConfirm else { return }
        let targets = OverlayInteractionModel.copyTargets(
            allItems: store.items,
            selectedIds: selection.selectedIds
        )
        guard !targets.isEmpty else {
            SoundFeedback.invalidAction()
            return
        }
        ClipboardCardView.writeCopyTargets(targets)
    }

    /// ⌘P：切换选中条目收藏（多选时整批设为与光标/首项相反状态）。
    private func handleToggleFavorite() {
        guard !showDeleteConfirm else { return }
        let ids = selection.selectedIds
        guard !ids.isEmpty else {
            SoundFeedback.invalidAction()
            return
        }
        let selected = OverlayInteractionModel.selectedItems(
            visibleItems: visibleItems,
            selectedIds: ids
        )
        guard let reference = OverlayInteractionModel.cursorPreviewItem(
            visibleItems: visibleItems,
            selectedIds: ids,
            cursorIndex: selection.cursorIndex
        ) ?? selected.first else {
            SoundFeedback.invalidAction()
            return
        }
        if ids.count > 1 {
            applyPins(ids, pinned: !reference.isPinned)
        } else {
            applyPin(reference)
        }
    }

    private func applyPin(_ item: ClipboardItem) {
        guard !store.togglePin(item) else {
            persistenceErrorMessage = nil
            retryPersistenceAction = nil
            return
        }
        persistenceErrorMessage = "该条目的收藏状态未改变，请重试。"
        retryPersistenceAction = { applyPin(item) }
    }

    private func applyPins(_ ids: Set<UUID>, pinned: Bool) {
        let result = store.setPinForSelected(ids, pinned: pinned)
        guard result.failed > 0 else {
            persistenceErrorMessage = nil
            retryPersistenceAction = nil
            return
        }
        persistenceErrorMessage = "已完成 \(result.completed) 项，\(result.failed) 项保存失败；已完成的状态会保留。"
        retryPersistenceAction = { applyPins(ids, pinned: pinned) }
    }

    /// Space：预览光标项（多选时仍只预览光标那一张）。
    private func handlePreviewCursor() {
        guard !showDeleteConfirm else { return }
        guard let item = OverlayInteractionModel.cursorPreviewItem(
            visibleItems: visibleItems,
            selectedIds: selection.selectedIds,
            cursorIndex: selection.cursorIndex
        ) else {
            SoundFeedback.invalidAction()
            return
        }
        guard let metadata = ClipboardItemPreviewBuilder.makeMetadata(for: item) else {
            SoundFeedback.invalidAction()
            return
        }
        let anchor = CardPreviewAnchorRegistry.view(for: item.id)
            ?? OverlayPanelManager.shared.previewAnchorView()
        guard let anchor else {
            SoundFeedback.invalidAction()
            return
        }
        QLPreviewHelper.shared.showPreview(metadata: metadata, from: anchor)
        DeveloperDiagnostics.record(DiagnosticsEvent.preview)
    }

    private func handleCommandPaste(_ note: Notification) {
        guard !showDeleteConfirm else { return }
        guard let idx = note.userInfo?["index"] as? Int else {
            SoundFeedback.invalidAction()
            return
        }
        let itemsByID = Dictionary(uniqueKeysWithValues: visibleItems.map { ($0.id, $0) })
        let shortcutItems = commandShortcutIds.compactMap { itemsByID[$0] }
        guard idx > 0, idx <= shortcutItems.count else {
            SoundFeedback.invalidAction()
            return
        }
        let item = shortcutItems[idx - 1]
        DeveloperDiagnostics.record(DiagnosticsEvent.pasteCmdNumber)
        Task { await OverlayPanelManager.shared.hideAndPaste(item) }
    }

    private func handleSearchEnterPaste() {
        guard !showDeleteConfirm else { return }
        guard let target = OverlayInteractionModel.cursorPreviewItem(
            visibleItems: visibleItems,
            selectedIds: selection.selectedIds,
            cursorIndex: selection.cursorIndex
        ) else {
            SoundFeedback.invalidAction()
            return
        }
        Task { await OverlayPanelManager.shared.hideAndPaste(target) }
    }

    // MARK: - 状态重置

    private func resetAllState() {
        showSearch = false
        isDockingDragActive = false
        showFilterPopover = false
        isSearchFocused = false
        OverlayPanelManager.shared.isSearchActive = false
        OverlayPanelManager.shared.isFilterPopoverActive = false
        OverlayPanelManager.shared.keyboardOwner = .overlayNavigation
        store.clearFilters(recordDiagnostics: false)
        renderedIds = []
        commandShortcutIds = []
        // 打开面板默认选中第一张卡片，便于立刻 Enter / 方向键 / Delete
        selectFirstVisibleCard()
    }
    private func prepareForPresentation() {
        resetAllState()
        trayPlacement = OverlayPanelManager.shared.currentPlacement
        isTrayPinned = OverlayPanelManager.shared.isPinned
        refreshAccessibilityPermission()
        updateLayoutForCurrentScreen()
        OverlayPanelManager.shared.isHorizontalCardLayout = isHorizontalLayout
        keyHandler.installMouseMonitor()
        prefetchAvailableAppIcons()
        withAnimation(reduceMotion ? nil : .spring(response: Local.Overlay.animationDuration, dampingFraction: UIConstants.Motion.damping)) {
            cardVisible = true
        }
    }

    private func tearDownAfterHide() {
        keyHandler.uninstall()
        iconPrefetchTask?.cancel()
        iconPrefetchTask = nil
        cardVisible = false
        showDeleteConfirm = false
        pendingDeleteIds = []
        showSearch = false
        showFilterPopover = false
        isSearchFocused = false
    }

    /// 当前可见列表的默认键盘落点：第一张卡片（空列表则清空选择）。
    private func selectFirstVisibleCard() {
        let items = store.filteredItems
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selection.selectFirst(visibleItems: items)
            stripScrollPosition.scrollTo(edge: .leading)
            sideScrollPosition.scrollTo(edge: .top)
            commandShortcutIds = items.prefix(9).map(\.id)
        }
    }

    // MARK: - 退场

    private func dismiss() {
        guard cardVisible else { return }
        keyHandler.uninstall()
        iconPrefetchTask?.cancel()
        iconPrefetchTask = nil
        showSearch = false
        showFilterPopover = false
        isSearchFocused = false
        OverlayPanelManager.shared.isSearchActive = false
        OverlayPanelManager.shared.isFilterPopoverActive = false
        OverlayPanelManager.shared.keyboardOwner = .overlayNavigation
        withAnimation(reduceMotion ? nil : .spring(response: Local.Overlay.animationDuration, dampingFraction: UIConstants.Motion.damping)) {
            cardVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : Local.Overlay.animationDuration)) {
            OverlayPanelManager.shared.hide()
        }
    }

    private func closeSearch() {
        guard showSearch else { return }
        store.searchQuery = ""
        withAnimation(searchExpansionAnimation) {
            showSearch = false
        }
    }

    // MARK: - 设置

    private func openSettingsFromOverlay() {
        OverlayPanelManager.shared.hide()
        store.clearFilters(recordDiagnostics: false)
        DispatchQueue.main.async {
            AppDelegate.shared?.openSettingsWindow()
        }
    }

    // MARK: - 批量删除

    private func deleteSelected() {
        let ids = pendingDeleteIds.isEmpty ? selection.selectedIds : pendingDeleteIds
        _ = store.deleteSelected(
            ids,
            clearSystemClipboardWhenEmpty: pendingClearClipboardWhenEmpty
        )
        // deleteSelected 会刷新 filteredItems；onChange 在 ID 列表变化时选中第一张。
        // 若删除未改变可见 ID 列表（例如删的是筛掉的项），仍强制回到第一张。
        selectFirstVisibleCard()
    }

    private func confirmDeleteSelected() {
        guard !pendingDeleteIds.isEmpty else {
            showDeleteConfirm = false
            return
        }
        deleteSelected()
        showDeleteConfirm = false
        pendingDeleteIds = []
        pendingClearClipboardWhenEmpty = true
        NotificationCenter.default.post(name: .overlayAlertActive,
                                        object: nil,
                                        userInfo: ["active": false])
    }

    private func cancelDeleteConfirm() {
        showDeleteConfirm = false
        pendingDeleteIds = []
        pendingClearClipboardWhenEmpty = true
        NotificationCenter.default.post(name: .overlayAlertActive,
                                        object: nil,
                                        userInfo: ["active": false])
    }

    /// - Parameter clearSystemClipboardWhenEmpty: 键盘 / 工具栏为 true；右键为 false（保留 ⌘V 内容）。
    private func requestDelete(ids: Set<UUID>, clearSystemClipboardWhenEmpty: Bool = true) {
        guard !ids.isEmpty else {
            SoundFeedback.invalidAction()
            return
        }
        pendingDeleteIds = ids
        pendingClearClipboardWhenEmpty = clearSystemClipboardWhenEmpty

        guard DeleteConfirmationPreference.requiresConfirmation else {
            deleteSelected()
            pendingDeleteIds = []
            pendingClearClipboardWhenEmpty = true
            return
        }

        NotificationCenter.default.post(name: .overlayAlertActive,
                                        object: nil,
                                        userInfo: ["active": true])
        withAnimation(.easeOut(duration: UIConstants.Motion.fast)) {
            showDeleteConfirm = true
        }
    }

    private var deleteConfirmOverlay: some View {
        ConfirmationOverlay(
            title: L10n["delete.confirm_title"],
            message: deleteConfirmMessage,
            cancelTitle: L10n["delete.confirm_cancel"],
            confirmTitle: L10n["delete.confirm_ok"],
            onCancel: cancelDeleteConfirm,
            onConfirm: confirmDeleteSelected
        )
        .animation(.easeOut(duration: UIConstants.Motion.fast), value: showDeleteConfirm)
    }

    private var deleteConfirmMessage: String {
        let favoriteCount = store.items.reduce(into: 0) { count, item in
            if pendingDeleteIds.contains(item.id), item.isPinned {
                count += 1
            }
        }
        if favoriteCount > 0 {
            return L10n["delete.confirm_msg_with_favorites", pendingDeleteIds.count, favoriteCount]
        }
        return L10n["delete.confirm_msg", pendingDeleteIds.count]
    }

    // MARK: - 搜索框（内联在 header 中）

    private var searchExpansionAnimation: Animation? {
        reduceMotion ? nil : .spring(response: UIConstants.Motion.medium, dampingFraction: UIConstants.Motion.damping)
    }

    private var searchControlHeight: CGFloat {
        Local.Overlay.toolbarButtonSize
    }

    private var searchControlWidth: CGFloat {
        guard showSearch else { return searchControlHeight }
        return trayPlacement.isSide
            ? Local.Overlay.compactSideSearchExpandedWidth
            : Local.Overlay.searchExpandedWidth
    }

    private var searchControl: some View {
        Group {
            if showSearch {
                searchControlContent
            } else {
                Button(action: openSearch) {
                    searchControlContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n["search.accessibility_label"])
                .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.searchButton)
            }
        }
        .padding(.trailing, Local.Overlay.searchTrailingPadding)
    }

    private var searchControlContent: some View {
        HStack(spacing: showSearch ? 6 : 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: showSearch ? UIConstants.TypeSize.callout : UIConstants.TypeSize.body, weight: .semibold))
                .foregroundColor(showSearch ? .white.opacity(UIConstants.OnDark.textTertiary) : toolbarForeground(isActive: false, isHovered: hoverSearch))
                .frame(width: showSearch ? UIConstants.Control.microIconSize : searchControlHeight, height: searchControlHeight)

            if showSearch {
                ZStack(alignment: .leading) {
                    if store.searchQuery.isEmpty {
                        Text(L10n["search.placeholder"])
                            .font(.system(size: UIConstants.TypeSize.body))
                            .foregroundColor(.white.opacity(UIConstants.OnDark.textSecondary))
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $store.searchQuery)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled(true)
                        .writingToolsBehavior(.disabled)
                        .font(.system(size: UIConstants.TypeSize.body))
                        .foregroundColor(.white.opacity(UIConstants.OnDark.textPrimary))
                        .focused($isSearchFocused)
                        .accessibilityLabel(L10n["search.accessibility_label"])
                        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.searchField)
                        .background(SearchFieldAutofillSuppressor())
                        .onExitCommand {
                            closeSearch()
                        }
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))

                Button {
                    store.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: UIConstants.TypeSize.label))
                        .frame(width: Local.Control.inlineActionSize, height: Local.Control.inlineActionSize)
                        .background(
                            Circle()
                                .fill(hoverClearSearch ? Color.white.opacity(UIConstants.OnDark.stroke) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(hoverClearSearch ? UIConstants.OnDark.textSecondary : UIConstants.OnDark.textFaint))
                .accessibilityLabel(L10n["search.clear"])
                .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.clearSearchButton)
                .opacity(store.searchQuery.isEmpty ? 0 : 1)
                .allowsHitTesting(!store.searchQuery.isEmpty)
                .onHover { hovering in
                    hoverClearSearch = hovering
                    if hovering { NSCursor.arrow.push() } else { NSCursor.pop() }
                }
                .animation(.easeOut(duration: UIConstants.Motion.instant), value: hoverClearSearch)

                if appleIntelligenceEnabled {
                    naturalLanguageSearchButton
                }

                searchCountBadge
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .padding(.horizontal, showSearch ? 10 : 0)
        .padding(.vertical, showSearch ? 6 : 0)
        .frame(width: searchControlWidth, height: searchControlHeight, alignment: .leading)
        .background(searchControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
        .scaleEffect(toolbarHoverScale(isHovered: !showSearch && hoverSearch))
        .onHover { hovering in
            hoverSearch = hovering
        }
        .animation(searchExpansionAnimation, value: showSearch)
        .animation(.easeOut(duration: UIConstants.Motion.instant), value: hoverSearch)
    }

    private func openSearch() {
        withAnimation(searchExpansionAnimation) { showSearch = true }
        DeveloperDiagnostics.record(DiagnosticsEvent.searchOpen)
    }

    private var naturalLanguageSearchButton: some View {
        Button {
            if naturalLanguageSearchHasIssue {
                showNaturalLanguageSearchStatus = true
                return
            }
            Task {
                await store.performNaturalLanguageSearch()
                if naturalLanguageSearchHasIssue {
                    showNaturalLanguageSearchStatus = true
                }
            }
        } label: {
            Group {
                switch store.naturalLanguageSearchState {
                case .searching:
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(UIConstants.OnDark.textSecondary))
                case .applied:
                    Image(systemName: "checkmark.circle.fill")
                case .unavailable, .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                case .idle:
                    Image(systemName: "sparkles")
                }
            }
            .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
            .frame(width: Local.Control.inlineActionSize, height: Local.Control.inlineActionSize)
        }
        .buttonStyle(.plain)
        .foregroundColor(.white.opacity(UIConstants.OnDark.textSecondary))
        .disabled(
            store.naturalLanguageSearchState == .searching
                || (store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !naturalLanguageSearchHasIssue)
        )
        .opacity(
            store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !naturalLanguageSearchHasIssue ? 0.45 : 1
        )
        .popover(isPresented: $showNaturalLanguageSearchStatus, arrowEdge: .bottom) {
            naturalLanguageSearchStatusPopover
                .presentationBackground(FilterPopoverStyle.surface)
                .presentationCornerRadius(UIConstants.Radius.panel)
        }
        .help(naturalLanguageSearchHelp)
        .accessibilityLabel(L10n["search.smart"])
        .accessibilityValue(naturalLanguageSearchHelp)
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.naturalLanguageSearchButton)
    }

    private var naturalLanguageSearchHasIssue: Bool {
        switch store.naturalLanguageSearchState {
        case .unavailable, .failed:
            return true
        case .idle, .searching, .applied:
            return false
        }
    }

    private var naturalLanguageSearchStatusPopover: some View {
        VStack(alignment: .leading, spacing: UIConstants.Card.contentVerticalPadding) {
            HStack(alignment: .top) {
                Label(L10n["search.smart_issue_title"], systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                    .foregroundStyle(PastryPalette.warmAccent)

                Spacer()

                Button {
                    showNaturalLanguageSearchStatus = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: UIConstants.TypeSize.caption, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n["a11y.close"])
            }

            Text(naturalLanguageSearchHelp)
                .font(.system(size: UIConstants.TypeSize.body))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n["search.smart_fallback_hint"])
                .font(.system(size: UIConstants.TypeSize.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(UIConstants.Overlay.cardSpacing)
        .frame(width: Local.Control.statusPopoverWidth)
    }

    private var naturalLanguageSearchHelp: String {
        switch store.naturalLanguageSearchState {
        case .idle:
            return L10n["search.smart"]
        case .searching:
            return L10n["search.smart_searching"]
        case .applied:
            return L10n["search.smart_applied"]
        case .failed:
            return L10n["search.smart_failed"]
        case .unavailable(.deviceNotEligible):
            return L10n["search.smart_unavailable_device"]
        case .unavailable(.appleIntelligenceNotEnabled):
            return L10n["search.smart_unavailable_disabled"]
        case .unavailable(.modelNotReady):
            return L10n["search.smart_unavailable_not_ready"]
        case .unavailable(.available):
            return L10n["search.smart_failed"]
        }
    }

    @ViewBuilder
    private var searchControlBackground: some View {
        if showSearch {
            overlaySearchFieldBackground
        } else {
            toolbarButtonBackground(isActive: false, isHovered: hoverSearch)
        }
    }

    // MARK: - 筛选按钮

    private var filterButton: some View {
        Button {
            // 打开前预热图标，减轻 popover 首帧卡顿（保持系统气泡形态）
            prefetchAvailableAppIcons()
            showFilterPopover.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                    .foregroundColor(toolbarForeground(isActive: showFilterPopover || hasActiveTimeOrTypeFilter, isHovered: hoverFilter))
                    .frame(width: Local.Overlay.toolbarButtonSize, height: Local.Overlay.toolbarButtonSize)

                if hasActiveTimeOrTypeFilter {
                    Circle()
                        .fill(PastryPalette.primaryActionFill)
                        .frame(
                            width: Local.Badge.indicatorDotSize,
                            height: Local.Badge.indicatorDotSize
                        )
                        .offset(
                            x: Local.Badge.indicatorDotOffset,
                            y: -Local.Badge.indicatorDotOffset
                        )
                        .transition(.scale(scale: 0.72).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: Local.Overlay.toolbarButtonSize, height: Local.Overlay.toolbarButtonSize)
            .background(toolbarButtonBackground(isActive: showFilterPopover || hasActiveTimeOrTypeFilter, isHovered: hoverFilter))
            .contentShape(RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoverFilter = hovering
            if hovering { NSCursor.arrow.push() } else { NSCursor.arrow.pop() }
        }
        .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
            FilterPopoverContent(store: store)
                .presentationBackground(FilterPopoverStyle.surface)
                .presentationCornerRadius(UIConstants.Radius.panel)
        }
        .scaleEffect(toolbarHoverScale(isHovered: hoverFilter))
        .animation(.easeOut(duration: UIConstants.Motion.instant), value: hoverFilter)
        .animation(.easeOut(duration: UIConstants.Motion.fast), value: hasActiveTimeOrTypeFilter)
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.filterButton)
        .accessibilityLabel(L10n["filter.title"])
        .accessibilityValue(hasActiveTimeOrTypeFilter ? L10n["filter.active_hint"] : "")
    }

    private var searchCountBadge: some View {
        let filtered = store.filteredItems.count
        let total = store.items.count
        let display = OverlayInteractionModel.searchCountDisplayText(
            filteredCount: filtered, totalCount: total
        )
        let reserve = OverlayInteractionModel.searchCountWidthReserveText(
            filteredCount: filtered, totalCount: total
        )
        return ZStack {
            // 不可见占位：按两侧最大位数预留等宽宽度，避免 count 变短时整行抖动
            Text(reserve)
                .hidden()
            Text(display)
        }
        .font(.system(size: UIConstants.TypeSize.caption, weight: .bold, design: .rounded))
        .foregroundColor(.white.opacity(UIConstants.OnDark.textSecondary))
        .monospacedDigit()
        .padding(.horizontal, Local.Badge.capsuleHorizontalPadding)
        .frame(height: Local.Badge.capsuleHeight)
        .background(
            Capsule(style: .continuous)
                .fill(.white.opacity(UIConstants.OnDark.fillSubtle))
        )
        .accessibilityLabel(display)
    }

    private var hasActiveTimeOrTypeFilter: Bool {
        store.typeFilter != nil
            || store.timeFilter != .any
            || store.appFilter != nil
            || store.handoffFilter
            || store.urlFilter
            || store.noteFilter != .any
    }

    // MARK: - 卡片容器

    @ViewBuilder
    private var cardContainer: some View {
        let displayItems = store.filteredItems

        // Single VStack: header + content (no nested wrapper stack).
        VStack(spacing: 0) {
            headerRow

            Group {
                if displayItems.isEmpty {
                    emptyState
                } else {
                    cardList(displayItems)
                        .padding(3)
                        // Constrain viewport so ScrollView can scroll instead of growing with content.
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 10)
            .frame(
                maxWidth: .infinity,
                minHeight: Local.Overlay.trayContentMinHeight,
                maxHeight: trayPlacement.isSide ? .infinity : nil
            )
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: trayPlacement.isSide ? .infinity : nil)
        .fixedSize(horizontal: false, vertical: !trayPlacement.isSide)
        .padding(.top, trayPlacement.isSide ? Local.Overlay.sideHeaderControlInset : 10)
        .padding(.horizontal, Local.Overlay.trayHorizontalPadding)
        .padding(.bottom, 10)
        .background(panelTrayBackground)
        // One outer clip for the tray; GlassBackground uses radius 0 (parent clips).
        .clipShape(RoundedRectangle(cornerRadius: Local.Overlay.trayCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.cardContainer)
    }

    private var panelTrayBackground: some View {
        ZStack {
            // Corner radius applied by the tray's outer clipShape only.
            GlassBackground(cornerRadius: 0)

            PastryPalette.sidebar.opacity(UIConstants.Overlay.overlaySurfaceTintOpacity)

            RoundedRectangle(cornerRadius: Local.Overlay.trayCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(UIConstants.OnDark.stroke), lineWidth: UIConstants.Stroke.hairline)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        if trayPlacement.isSide {
            VStack(spacing: 8) {
                if selection.selectedIds.count > 1 || !accessibilityTrusted {
                    headerStatusContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                }

                HStack(spacing: 0) {
                    searchControl

                    if !showSearch {
                        filterAndTabControls
                    }

                    Spacer(minLength: 0)
                    trayUtilityControls
                }
            }
            .padding(.horizontal, Local.Overlay.sideHeaderHorizontalPadding)
            .background(TrayDragHandle())
        } else {
            HStack(spacing: 0) {
                headerStatusContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()

                HStack(spacing: 0) {
                    searchControl
                    filterAndTabControls
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)

                HStack {
                    Spacer()
                    trayUtilityControls
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .background(TrayDragHandle())
        }
    }

    private var headerStatusContent: some View {
        HStack(spacing: UIConstants.Overlay.cardSpacing) {
            if selection.selectedIds.count > 1 {
                multiSelectToolbarLeading
            }
            if !accessibilityTrusted {
                accessibilityPermissionBanner
            }
        }
    }

    private var filterAndTabControls: some View {
        HStack(spacing: 0) {
            filterButton
                .padding(.trailing, 6)

            tabButton(tab: .all, icon: "tray.full", label: L10n["tab.all"], isSelected: store.pinTab == .all)
                .padding(.trailing, 6)
            tabButton(tab: .pinned, icon: "bookmark.fill", label: L10n["tab.pinned"], isSelected: store.pinTab == .pinned)
        }
    }

    private var trayUtilityControls: some View {
        HStack(spacing: Local.Overlay.sideUtilityControlsSpacing) {
            pinTrayButton
            settingsButton
        }
    }

    private var pinTrayButton: some View {
        Button {
            isTrayPinned = OverlayPanelManager.shared.togglePinned()
        } label: {
            Image(systemName: isTrayPinned ? "pin.fill" : "pin")
                .font(.system(size: UIConstants.TypeSize.title, weight: .semibold))
                .foregroundColor(toolbarForeground(isActive: isTrayPinned, isHovered: hoverPin))
                .frame(width: Local.Overlay.toolbarButtonSize, height: Local.Overlay.toolbarButtonSize)
                .background(toolbarButtonBackground(isActive: isTrayPinned, isHovered: hoverPin))
        }
        .buttonStyle(.plain)
        .help(L10n[isTrayPinned ? "toolbar.unpin_tray" : "toolbar.pin_tray"])
        .accessibilityLabel(L10n[isTrayPinned ? "toolbar.unpin_tray" : "toolbar.pin_tray"])
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.pinTrayButton)
        .onHover { hoverPin = $0 }
    }

    private var settingsButton: some View {
        Button {
            openSettingsFromOverlay()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: UIConstants.TypeSize.title, weight: .semibold))
                .foregroundColor(toolbarForeground(isActive: false, isHovered: hoverGear))
                .frame(width: Local.Overlay.toolbarButtonSize, height: Local.Overlay.toolbarButtonSize)
                .background(toolbarButtonBackground(isActive: false, isHovered: hoverGear))
        }
        .buttonStyle(.plain)
        .scaleEffect(toolbarHoverScale(isHovered: hoverGear))
        .animation(.easeOut(duration: UIConstants.Motion.instant), value: hoverGear)
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.settingsButton)
        .onHover { hoverGear = $0 }
    }

    private var multiSelectToolbarLeading: some View {
        HStack(spacing: 8) {
            Text(L10n["toolbar.selected_count", selection.selectedIds.count])
                .font(.system(size: UIConstants.TypeSize.label))
                .foregroundColor(.white.opacity(UIConstants.OnDark.textSecondary))
                .fixedSize()

            HStack(spacing: 4) {
                multiSelectActionButton(
                    action: .paste,
                    icon: AppIcons.paste,
                    label: L10n["help.usage.paste"],
                    accessibilityId: AccessibilityIdentifiers.Overlay.multiPasteButton
                ) {
                    handleConfirmPaste()
                }
                multiSelectActionButton(
                    action: .copy,
                    icon: AppIcons.copy,
                    label: L10n["context.copy"],
                    accessibilityId: AccessibilityIdentifiers.Overlay.multiCopyButton
                ) {
                    handleCopySelected()
                }
                multiSelectActionButton(
                    action: .smart,
                    icon: "sparkles",
                    label: multiSmartActionLabel,
                    accessibilityId: AccessibilityIdentifiers.Overlay.multiSmartActionButton,
                    isEnabled: multiSmartActionEnabled
                ) {
                    SmartActionPanelManager.shared.show(for: multiSmartActionItems)
                }
                multiSelectActionButton(
                    action: .delete,
                    icon: AppIcons.delete,
                    label: L10n["context.delete"],
                    accessibilityId: AccessibilityIdentifiers.Overlay.multiDeleteButton
                ) {
                    handleDeleteSelectedRequest()
                }
            }
        }
    }

    private func multiSelectActionButton(
        action: MultiSelectToolbarAction,
        icon: String,
        label: String,
        accessibilityId: String,
        isEnabled: Bool = true,
        perform: @escaping () -> Void
    ) -> some View {
        let isHovered = hoverMultiAction == action
        return Button(action: perform) {
            Image(systemName: icon)
                .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                .foregroundColor(toolbarForeground(isActive: false, isHovered: isHovered))
                .frame(width: Local.Overlay.toolbarButtonSize, height: Local.Overlay.toolbarButtonSize)
                .background(toolbarButtonBackground(isActive: false, isHovered: isHovered))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(accessibilityId)
        .disabled(!isEnabled)
        .scaleEffect(toolbarHoverScale(isHovered: isHovered))
        .animation(.easeOut(duration: UIConstants.Motion.instant), value: isHovered)
        .onHover { hovering in
            if hovering {
                hoverMultiAction = action
            } else if hoverMultiAction == action {
                hoverMultiAction = nil
            }
        }
    }

    private var multiSmartActionItems: [ClipboardItem] {
        visibleItems.filter { selection.selectedIds.contains($0.id) }
    }

    private var multiSmartActionEnabled: Bool {
        appleIntelligenceEnabled
            && MultiSmartActionSelection.mode(for: multiSmartActionItems) != nil
    }

    private var multiSmartActionLabel: String {
        guard appleIntelligenceEnabled else {
            return L10n["smart_action.multi.disabled.preference"]
        }
        guard multiSmartActionItems.count <= MultiSmartActionSelection.maximumItemCount else {
            return L10n[
                "smart_action.multi.disabled.limit",
                MultiSmartActionSelection.maximumItemCount
            ]
        }
        guard MultiSmartActionSelection.mode(for: multiSmartActionItems) != nil else {
            return L10n["smart_action.multi.disabled.format"]
        }
        return L10n["smart_action.multi.toolbar"]
    }

    private func tabButton(tab: StoreManager.PinTab, icon: String, label: String, isSelected: Bool) -> some View {
        let showsLabel = !showSearch && !trayPlacement.isSide
        return Button {
            store.pinTab = tab
            selectFirstVisibleCard()
        } label: {
            let isHover = hoverTab == tab
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                    .frame(
                        width: showsLabel
                            ? UIConstants.TypeSize.body + 2
                            : Local.Overlay.toolbarButtonSize,
                        alignment: .center
                    )
                if showsLabel {
                    Text(label)
                        .font(.system(size: UIConstants.TypeSize.label))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, showsLabel ? 10 : 0)
            .padding(.vertical, showsLabel ? 4 : 0)
            .frame(height: Local.Overlay.toolbarButtonSize)
            .foregroundColor(toolbarForeground(isActive: isSelected, isHovered: isHover))
            .background(toolbarButtonBackground(isActive: isSelected, isHovered: isHover))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .scaleEffect(toolbarHoverScale(isHovered: hoverTab == tab))
        .animation(.easeOut(duration: UIConstants.Motion.instant), value: hoverTab)
        .accessibilityIdentifier(tab == .all ? AccessibilityIdentifiers.Overlay.allTab : AccessibilityIdentifiers.Overlay.pinnedTab)
        .onHover { hovering in
            hoverTab = hovering ? tab : nil
        }
    }

    private var overlaySearchFieldBackground: some View {
        RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
            .fill(Color.black.opacity(Local.Overlay.searchFieldWellOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                    .stroke(Color.white.opacity(UIConstants.OnDark.fillSubtle), lineWidth: UIConstants.Stroke.hairline)
            )
    }

    private func toolbarForeground(isActive: Bool, isHovered: Bool) -> Color {
        if isActive {
            return .white
        }
        return .white.opacity(isHovered ? UIConstants.OnDark.textPrimary : UIConstants.OnDark.textIdle)
    }

    private func toolbarHoverScale(isHovered: Bool) -> CGFloat {
        guard !reduceMotion else { return 1 }
        return showFilterPopover ? 1 : (isHovered ? 1.015 : 1)
    }

    /// Flat chip chrome: one fill, optional single hairline. No dual strokes / bevel shadows.
    private func toolbarButtonBackground(isActive: Bool, isHovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
            .fill(toolbarButtonFill(isActive: isActive, isHovered: isHovered))
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                    .stroke(toolbarButtonBorder(isActive: isActive, isHovered: isHovered), lineWidth: UIConstants.Stroke.hairline)
            )
    }

    private func toolbarButtonFill(isActive: Bool, isHovered: Bool) -> Color {
        if isActive {
            return PastryPalette.primaryActionFill
        }
        return .white.opacity(isHovered ? UIConstants.OnDark.fillHover : UIConstants.OnDark.fillSubtle)
    }

    private func toolbarButtonBorder(isActive: Bool, isHovered: Bool) -> Color {
        if isActive {
            return PastryPalette.primaryActionFill.opacity(UIConstants.Overlay.accentSoftOpacity)
        }
        // Idle: no visible border — fill alone defines the control.
        return .white.opacity(isHovered ? UIConstants.OnDark.fillSubtle : 0)
    }

    // MARK: - 卡片列表

    /// 底部托盘在宽屏使用横向卡带；左右托盘固定为纵向卡片列表。
    /// 初始化时同步读取 NSEvent/NSScreen（SwiftUI body 在主线程，安全）。
    /// 若将来在此处引入后台调用，需改为主线程异步赋值。
    @State private var isHorizontalLayout: Bool = {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        let width = screen?.frame.width ?? NSScreen.main?.frame.width ?? 1_440
        return TrayPlacementPreferences.effectivePlacement().usesHorizontalCards(screenWidth: width)
    }()

    /// 屏幕配置变化时重新评估布局方向（用户拖面板到不同分辨率屏幕）
    private func updateLayoutForCurrentScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        let width = screen?.frame.width ?? NSScreen.main?.frame.width ?? 1_440
        let useHorizontal = trayPlacement.usesHorizontalCards(screenWidth: width)
        if useHorizontal != isHorizontalLayout {
            isHorizontalLayout = useHorizontal
            OverlayPanelManager.shared.isHorizontalCardLayout = useHorizontal
            stripScrollPosition.scrollTo(edge: .leading)
            sideScrollPosition.scrollTo(edge: .top)
        }
    }

    /// 连续应用设备的像素 delta；快速滚动时使用驱动提供的较大增量形成自然加速。
    private func handleHorizontalStripScroll(_ note: Notification) {
        let delta = (note.userInfo?["delta"] as? CGFloat)
            ?? (note.userInfo?["delta"] as? Double).map { CGFloat($0) }
            ?? 0
        guard abs(delta) > 0.01 else { return }

        let result = OverlayInteractionModel.applyStripPixelScroll(
            offsetX: stripScrollGeometry.offsetX,
            delta: delta,
            maxOffsetX: stripScrollGeometry.maxOffsetX
        )
        if abs(result.offsetX - stripScrollGeometry.offsetX) > 0.01 {
            // 先更新本地偏移，避免高频事件在 geometry 回调前反复基于旧位置计算。
            stripScrollGeometry.offsetX = result.offsetX
            stripScrollPosition.scrollTo(x: result.offsetX)
        }
        if result.hitLeading {
            showStripEdgeGlow(towardHigherIndex: false)
        } else if result.hitTrailing {
            showStripEdgeGlow(towardHigherIndex: true)
        }
    }

    private func showStripEdgeGlow(towardHigherIndex: Bool) {
        let side: StripEdgeSide = towardHigherIndex ? .trailing : .leading
        withAnimation(reduceMotion ? nil : .spring(response: UIConstants.Motion.slow, dampingFraction: UIConstants.Motion.damping)) {
            stripEdgeGlow = side
        }

        let now = CFAbsoluteTimeGetCurrent()
        if now - lastStripEdgeHapticAt > 0.4 {
            lastStripEdgeHapticAt = now
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }

        stripEdgeGlowClearTask?.cancel()
        stripEdgeGlowClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 340_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.medium)) {
                if stripEdgeGlow == side {
                    stripEdgeGlow = nil
                }
            }
        }
    }

    /// 尽头指示：贴卡带视口边缘的短暖金竖条，不铺渐变（避免照出卡片外留白）。
    private func stripEdgeGlowOverlay(side: StripEdgeSide) -> some View {
        let visible = stripEdgeGlow == side
        return Capsule(style: .continuous)
            .fill(PastryPalette.warmAccent.opacity(visible ? UIConstants.OnDark.textPrimary : 0))
            .frame(
                width: Local.Overlay.insertIndicatorWidth,
                height: visible
                    ? Local.Overlay.insertIndicatorHeightVisible
                    : Local.Overlay.insertIndicatorHeightHidden
            )
            .shadow(
                color: PastryPalette.warmAccent.opacity(visible ? UIConstants.Overlay.accentSoftOpacity : 0),
                radius: visible ? UIConstants.Shadow.Icon.radius : 0
            )
            .padding(side == .leading ? .leading : .trailing, 8)
            .frame(maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .scaleEffect(y: visible ? 1 : 0.75, anchor: .center)
    }

    @ViewBuilder
    private func cardList(_ items: [ClipboardItem]) -> some View {
        if isHorizontalLayout {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: UIConstants.Overlay.cardSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        cardView(item, index: idx)
                            .id(item.id)
                    }
                }
                .padding(.vertical, 3)
                // 无左右 padding：首尾卡贴视口边，尽头指示不会落在虚空留白上
                .scrollTargetLayout()
            }
            .scrollPosition($stripScrollPosition)
            .onScrollTargetVisibilityChange(idType: UUID.self) { ids in
                commandShortcutIds = OverlayInteractionModel.commandShortcutItemIDs(
                    orderedItemIDs: items.map(\.id),
                    viewportItemIDs: ids
                )
            }
            .onScrollGeometryChange(for: StripScrollGeometry.self) { geometry in
                StripScrollGeometry(
                    offsetX: max(0, geometry.contentOffset.x),
                    maxOffsetX: max(0, geometry.contentSize.width - geometry.containerSize.width)
                )
            } action: { _, geometry in
                stripScrollGeometry = geometry
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) { stripEdgeGlowOverlay(side: .leading) }
            .overlay(alignment: .trailing) { stripEdgeGlowOverlay(side: .trailing) }
            .animation(nil, value: items.count)
            .onAppear {
                OverlayPanelManager.shared.isHorizontalCardLayout = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayCardStripScroll)) { note in
                handleHorizontalStripScroll(note)
            }
            .onChange(of: selection.cursorIndex) { oldIdx, newIdx in
                guard let idx = newIdx, idx < items.count else { return }
                let rendered = renderedIds.contains(items[idx].id)
                let downward = (oldIdx ?? 0) < idx
                let neighborIdx = downward ? idx + 1 : idx - 1
                let neighborMissing = neighborIdx >= 0 && neighborIdx < items.count
                    && !renderedIds.contains(items[neighborIdx].id)
                guard !rendered || neighborMissing else { return }
                // 滚动目标：边缘时滚动邻卡（露出下一张），否则滚动当前卡
                let scrollId = neighborMissing ? items[neighborIdx].id : items[idx].id
                withAnimation(.easeInOut(duration: UIConstants.Motion.fast)) {
                    stripScrollPosition.scrollTo(
                        id: scrollId,
                        anchor: downward ? .trailing : .leading
                    )
                }
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: UIConstants.Overlay.cardSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        cardView(item, index: idx)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .scrollTargetLayout()
            }
            .scrollPosition($sideScrollPosition)
            .frame(maxWidth: Local.Overlay.compactListMaxWidth)
            .onScrollTargetVisibilityChange(idType: UUID.self) { ids in
                commandShortcutIds = OverlayInteractionModel.commandShortcutItemIDs(
                    orderedItemIDs: items.map(\.id),
                    viewportItemIDs: ids
                )
            }
            .animation(nil, value: items.count)
            .onAppear {
                OverlayPanelManager.shared.isHorizontalCardLayout = false
            }
            .onChange(of: selection.cursorIndex) { oldIdx, newIdx in
                guard let idx = newIdx, idx < items.count else { return }
                let rendered = renderedIds.contains(items[idx].id)
                let downward = (oldIdx ?? 0) < idx
                let neighborIdx = downward ? idx + 1 : idx - 1
                let neighborMissing = neighborIdx >= 0 && neighborIdx < items.count
                    && !renderedIds.contains(items[neighborIdx].id)
                guard !rendered || neighborMissing else { return }
                let scrollId = neighborMissing ? items[neighborIdx].id : items[idx].id
                let anchor: UnitPoint = downward ? .bottom : .top
                withAnimation(.easeInOut(duration: UIConstants.Motion.fast)) {
                    sideScrollPosition.scrollTo(id: scrollId, anchor: anchor)
                }
            }
        }
    }

    @ViewBuilder
    private func cardView(_ item: ClipboardItem, index: Int) -> some View {
        let isInMultiSelection = selection.selectedIds.count > 1 && selection.selectedIds.contains(item.id)
        let insertRole = Self.cardInsertRole(for: item.id, animation: store.insertAnimation)
        ClipboardCardView(
            item: item,
            isSelected: selection.selectedIds.contains(item.id),
            cmdBadgeIndex: OverlayInteractionModel.commandBadgeIndex(
                cmdDown: cmdDown,
                itemID: item.id,
                shortcutItemIDs: commandShortcutIds
            ),
            presentation: trayPlacement.isSide ? .compactSide : .card,
            selectedIds: Binding(
                get: { selection.selectedIds },
                set: { selection.selectedIds = $0 }
            ),
            onTap: { tapped in
                handleCardTap(tapped)
            },
            onPin: { tapped, ids in
                // 多选且落点在选中集合内 → 整批收藏/取消；否则只动本卡
                if ids.count > 1, ids.contains(tapped.id) {
                    applyPins(ids, pinned: !tapped.isPinned)
                } else {
                    applyPin(tapped)
                }
            },
            onDelete: { deleted in
                // 多选且落点在选中集合内 → 整批删除；否则只删本卡
                if selection.selectedIds.count > 1, selection.selectedIds.contains(deleted.id) {
                    requestDelete(ids: selection.selectedIds, clearSystemClipboardWhenEmpty: false)
                } else {
                    requestDelete(ids: [deleted.id], clearSystemClipboardWhenEmpty: false)
                }
            }
        )
        .id(item.id)
        .modifier(CardInsertAppearance(
            role: insertRole,
            axis: isHorizontalLayout ? .horizontal : .vertical,
            step: trayPlacement.isSide
                ? Local.Overlay.compactRowInsertPushDistance
                : Local.Overlay.regularCardInsertPushDistance
        ))
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.card(item.id.uuidString))
        .onAppear { renderedIds.insert(item.id) }
        .onDisappear { renderedIds.remove(item.id) }
        // 多选拖拽也走 SwiftUI .onDrag：不再用 AppKit 覆盖层——
        // 覆盖层会吃掉左键 mouseDown，⌘/⇧ 点选永远到不了卡片手势。
        .onDrag {
            OverlayPanelManager.shared.beginDragThrough()
            if isInMultiSelection {
                let selected = visibleItems.filter { selection.selectedIds.contains($0.id) }
                DeveloperDiagnostics.record(DiagnosticsEvent.dragMulti)
                return DragPayloadBuilder.providerForSelection(selected) { item in
                    DatabaseManager.shared.loadFullContent(id: item.id)
                }
            } else {
                DeveloperDiagnostics.record(DiagnosticsEvent.dragSingle)
                return DragPayloadBuilder.provider(for: item) { item in
                    DatabaseManager.shared.loadFullContent(id: item.id)
                }
            }
        }
    }

    private static func cardInsertRole(
        for id: UUID,
        animation: ClipboardInsertAnimation?
    ) -> CardInsertAppearance.Role {
        guard let animation else { return .none }
        if id == animation.newID {
            return animation.promoteFromIndex > 0
                ? .flyingIn(steps: animation.promoteFromIndex)
                : .fadingIn
        }
        if animation.shiftingIDs.contains(id) {
            return .shiftingBack
        }
        return .none
    }

    // MARK: - 选择交互

    /// 卡片单击：委托可测管线（修饰键解析 + SelectionState）
    private func handleCardTap(_ item: ClipboardItem) {
        // currentEvent ∪ live flags；mouseDown monitor 再兜底（SwiftUI gesture 常丢 ⌘/⇧）
        let flags = OverlayInteractionModel.readCardTapModifierFlags()
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: item,
            eventCommand: flags.command,
            eventShift: flags.shift,
            monitoredCommand: keyHandler.lastMouseHasCommand,
            monitoredShift: keyHandler.lastMouseHasShift,
            visibleItems: visibleItems
        )
    }


    // MARK: - 键盘事件

    /// 获取当前显示中的 items
    private var visibleItems: [ClipboardItem] {
        store.filteredItems
    }

    private var pageNavigationStep: Int {
        isHorizontalLayout ? 3 : 4
    }

    /// 处理键盘导航通知：方向键、翻页、首尾跳转统一进入这里。
    private func handleCursorMove(_ note: Notification) {
        let extend = note.userInfo?["extend"] as? Bool ?? false
        if let target = note.userInfo?["target"] as? String {
            switch target {
            case "home":
                moveCursor(to: 0, extend: extend)
            case "end":
                moveCursor(to: visibleItems.count - 1, extend: extend)
            default:
                SoundFeedback.invalidAction()
            }
            return
        }
        if let pageDelta = note.userInfo?["pageDelta"] as? Int {
            moveCursor(delta: pageDelta * pageNavigationStep, extend: extend)
            return
        }
        if let delta = note.userInfo?["delta"] as? Int {
            moveCursor(delta: delta, extend: extend)
        }
    }

    /// 方向键导航：委托给 SelectionState；已在边界再按同向时与侧滚一样给边缘光晕。
    private func moveCursor(delta: Int, extend: Bool) {
        if selection.wouldHitBoundary(delta: delta, visibleItems: visibleItems) {
            SoundFeedback.invalidAction()
            if isHorizontalLayout,
               let towardHigher = OverlayInteractionModel.stripEdgeTowardHigherIndex(forKeyboardDelta: delta) {
                showStripEdgeGlow(towardHigherIndex: towardHigher)
            }
            return
        }
        selection.moveCursor(delta: delta, extend: extend, visibleItems: visibleItems)
    }

    private func moveCursor(to targetIndex: Int, extend: Bool) {
        if selection.wouldHitBoundary(targetIndex: targetIndex, visibleItems: visibleItems) {
            SoundFeedback.invalidAction()
            if isHorizontalLayout,
               let towardHigher = OverlayInteractionModel.stripEdgeTowardHigherIndex(
                   forAbsoluteTarget: targetIndex,
                   itemCount: visibleItems.count
               ) {
                showStripEdgeGlow(towardHigherIndex: towardHigher)
            }
            return
        }
        selection.moveCursor(to: targetIndex, extend: extend, visibleItems: visibleItems)
    }

    private func prefetchAvailableAppIcons() {
        let apps = store.availableApps
        guard !apps.isEmpty else { return }
        // 不取消已有任务：筛选打开时再调一次可补全未完成的预取，避免 cancel 导致首帧仍 miss cache
        if iconPrefetchTask == nil || iconPrefetchTask?.isCancelled == true {
            iconPrefetchTask = Task.detached(priority: .userInitiated) {
                for app in apps.prefix(32) {
                    guard !Task.isCancelled else { return }
                    // themeColor 内部会暖 icon + color，供卡片首帧 cached* 命中
                    _ = AppIconProvider.shared.themeColor(for: app)
                }
            }
        } else {
            // 已有预取在跑时，并行补一轮高优先级剩余（有缓存则很快）
            Task.detached(priority: .userInitiated) {
                for app in apps.prefix(32) {
                    _ = AppIconProvider.shared.themeColor(for: app)
                }
            }
        }
    }

    // MARK: - 辅助功能 banner

    private var accessibilityPermissionBanner: some View {
        Button {
            AccessibilityPermissionChecker.openSystemSettings()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: UIConstants.TypeSize.caption, weight: .medium))
                    .foregroundColor(PastryPalette.warmGoldSoft)

                Text(L10n["overlay.accessibility_banner"])
                    .font(.system(size: UIConstants.TypeSize.label, weight: .medium))
                    .foregroundColor(.white.opacity(UIConstants.OnDark.textSecondary))
                    .lineLimit(1)

                Text("→")
                    .font(.system(size: UIConstants.TypeSize.label, weight: .medium))
                    .foregroundColor(PastryPalette.warmGoldSoft.opacity(UIConstants.OnDark.textTertiary))

                Text(L10n["overlay.accessibility_banner_action"])
                    .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                    .foregroundColor(PastryPalette.warmGoldSoft)
            }
            .padding(.horizontal, UIConstants.Overlay.cardSpacing)
            .frame(height: Local.Overlay.toolbarButtonSize)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                    .fill(PastryPalette.warmAccent.opacity(UIConstants.Overlay.accentFillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                            .stroke(PastryPalette.warmAccent.opacity(UIConstants.Overlay.accentSoftOpacity), lineWidth: UIConstants.Stroke.hairline)
                    )
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.accessibilityBanner)
    }

    private func refreshAccessibilityPermission() {
        accessibilityTrusted = AccessibilityPermissionChecker.shared.isTrusted()
    }

    // MARK: - 空状态

    private var emptyState: some View {
        let hasActiveFilters = OverlayInteractionModel.hasActiveFilters(
            searchQuery: store.searchQuery,
            typeFilter: store.typeFilter,
            appFilter: store.appFilter,
            timeFilter: store.timeFilter,
            urlFilter: store.urlFilter,
            handoffFilter: store.handoffFilter,
            noteFilter: store.noteFilter
        )
        let model = OverlayEmptyStateModel.resolve(
            isPinnedTab: store.pinTab == .pinned,
            hasActiveFilters: hasActiveFilters
        )

        return VStack {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Image(systemName: model.icon)
                    .font(.system(size: UIConstants.TypeSize.display, weight: .semibold))
                    .foregroundColor(.white.opacity(UIConstants.OnDark.textSecondary))
                    .padding(.bottom, 4)

                Text(model.title)
                    .font(.system(size: UIConstants.TypeSize.title, weight: .semibold))
                    .foregroundColor(.white.opacity(UIConstants.OnDark.textPrimary))

                Text(model.subtitle)
                    .font(.system(size: UIConstants.TypeSize.callout))
                    .foregroundColor(.white.opacity(UIConstants.OnDark.textTertiary))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .frame(maxWidth: Local.Overlay.emptyStateMaxWidth)

                if model.showsCopyTryHint {
                    emptyHistoryCopyHint
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, Local.Overlay.horizontalPadding)
            .padding(.vertical, Local.Overlay.emptyStateVerticalPadding)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Local.Overlay.horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: Local.Overlay.emptyStateMinHeight)
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.emptyState)
    }

    /// 空历史示意：⌘C 键帽 +「复制任意内容试试」
    private var emptyHistoryCopyHint: some View {
        HStack(spacing: 10) {
            // 键帽示意
            Text("⌘C")
                .font(.system(size: UIConstants.TypeSize.label, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(UIConstants.Settings.pressedOpacity))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.control, style: .continuous)
                        .fill(Color.white.opacity(UIConstants.OnDark.fillSubtle))
                        .overlay(
                            RoundedRectangle(cornerRadius: UIConstants.Radius.control, style: .continuous)
                                .strokeBorder(Color.white.opacity(UIConstants.OnDark.stroke), lineWidth: UIConstants.Stroke.hairline)
                        )
                        .shadow(
                            color: .black.opacity(Local.Keycap.shadowOpacity),
                            radius: 0,
                            x: 0,
                            y: Local.Keycap.shadowY
                        )
                )

            Image(systemName: "arrow.right")
                .font(.system(size: UIConstants.TypeSize.caption, weight: .semibold))
                .foregroundColor(.white.opacity(UIConstants.OnDark.textFaint))

            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                Text(L10n["empty.copy_try_hint"])
                    .font(.system(size: UIConstants.TypeSize.callout, weight: .medium))
            }
            .foregroundColor(.white.opacity(UIConstants.OnDark.textSecondary))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.panel, style: .continuous)
                .fill(Color.white.opacity(UIConstants.OnDark.fillSubtle))
                .overlay(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.panel, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(UIConstants.OnDark.fillHover),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
        )
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.emptyCopyHint)
    }
}
private struct TrayDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TrayDragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class TrayDragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        OverlayPanelManager.shared.beginPanelDockingDrag()
    }
}


// MARK: - 相关卡入场位移（置顶项之前的卡让位；之后的卡不动）

private struct CardInsertAppearance: ViewModifier {
    enum Role: Equatable {
        case none
        case fadingIn
        case flyingIn(steps: Int)
        case shiftingBack
    }

    enum Axis {
        case horizontal
        case vertical
    }

    let role: Role
    let axis: Axis
    let step: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(x: axis == .horizontal ? offset : 0, y: axis == .vertical ? offset : 0)
            .onAppear { runIfNeeded() }
            .onChange(of: role) { _, _ in runIfNeeded() }
    }

    private var opacity: Double {
        if reduceMotion { return 1 }
        guard !settled else { return 1 }
        switch role {
        case .fadingIn:
            return 0
        case .flyingIn, .shiftingBack, .none:
            return 1
        }
    }

    private var offset: CGFloat {
        if reduceMotion { return 0 }
        guard !settled else { return 0 }
        switch role {
        case .none, .fadingIn:
            return 0
        case .flyingIn(let steps):
            return CGFloat(steps) * step
        case .shiftingBack:
            return -step
        }
    }

    private func runIfNeeded() {
        guard role != .none else {
            settled = true
            return
        }
        settled = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.fast)) {
            settled = true
        }
    }
}

// MARK: - 键盘/鼠标事件处理器（类实例，避免 struct 捕获问题）
/// 非 private：`ClipboardOverlayPanel` 侧滚轮兜底需要调用静态解析方法。
final class KeyboardEventHandler: ObservableObject {
    private(set) var lastMouseHasCommand = false
    private(set) var lastMouseHasShift = false

    private var mouseMonitor: Any?
    private var scrollMonitor: Any?

    /// 从 NSEvent / CGEvent 提取卡带 delta。
    /// 侧轮优先并限制加速幅度；没有侧向输入时映射普通滚轮并保留其加速。
    static func cardStripDelta(from event: NSEvent) -> CGFloat? {
        let cg = event.cgEvent
        return OverlayInteractionModel.normalizedCardStripDelta(
            hasPreciseDeltas: event.hasPreciseScrollingDeltas,
            scrollingDeltaX: event.scrollingDeltaX,
            legacyDeltaX: event.deltaX,
            pointDeltaX: CGFloat(cg?.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) ?? 0),
            fixedDeltaX: CGFloat(cg?.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) ?? 0),
            lineDeltaX: CGFloat(cg?.getDoubleValueField(.scrollWheelEventDeltaAxis2) ?? 0),
            scrollingDeltaY: event.scrollingDeltaY,
            legacyDeltaY: event.deltaY,
            pointDeltaY: CGFloat(cg?.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) ?? 0),
            fixedDeltaY: CGFloat(cg?.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) ?? 0),
            lineDeltaY: CGFloat(cg?.getDoubleValueField(.scrollWheelEventDeltaAxis1) ?? 0)
        )
    }

    /// 托盘面板上的 SwiftUI 横向 ScrollView 常收不到侧滚轮；在 AppKit 层桥接。
    static func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard OverlayPanelManager.shared.shouldRouteCardStripScroll(event) else { return event }
        guard let delta = cardStripDelta(from: event) else { return event }

        NotificationCenter.default.post(
            name: .overlayCardStripScroll,
            object: nil,
            userInfo: ["delta": delta]
        )
        return nil
    }

    func installMouseMonitor() {
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                let flags = OverlayInteractionModel.normalizedModifierFlags(event.modifierFlags)
                self?.lastMouseHasCommand = flags.contains(.command)
                self?.lastMouseHasShift = flags.contains(.shift)
                // applicationDefined 预览：点外部只关预览，不连带关托盘
                if QLPreviewHelper.shared.isShowing, !QLPreviewHelper.shared.contains(event) {
                    QLPreviewHelper.shared.dismiss()
                    return nil
                }
                return event
            }
        }
        if scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                Self.handleScrollWheel(event)
            }
        }
    }

    func uninstall() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
    }
}
