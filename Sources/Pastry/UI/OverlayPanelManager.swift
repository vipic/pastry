import Cocoa
import SwiftUI
import OSLog

// MARK: - 自定义覆盖层面板
final class ClipboardOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.keyCode == 53,
           OverlayPanelManager.shared.keyboardOwner == .searchField,
           !OverlayPanelManager.shared.isAlertActive {
            routeCancelKey()
            return
        }
        if event.type == .keyDown,
           Self.isSearchShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags),
           OverlayPanelManager.shared.keyboardOwner != .favoriteNoteEditor,
           !OverlayPanelManager.shared.isAlertActive {
            routeOpenSearchKey()
            return
        }
        // 部分鼠标侧滚轮事件会先到 panel 而不是 local monitor；与 KeyboardEventHandler 共用解析。
        if event.type == .scrollWheel,
           OverlayPanelManager.shared.isHorizontalCardLayout,
           !OverlayPanelManager.shared.isAlertActive,
           KeyboardEventHandler.cardStripDelta(from: event) != nil {
            _ = KeyboardEventHandler.handleScrollWheel(event)
            return
        }
        super.sendEvent(event)
    }

    override func scrollWheel(with event: NSEvent) {
        if OverlayPanelManager.shared.isHorizontalCardLayout,
           !OverlayPanelManager.shared.isAlertActive,
           KeyboardEventHandler.cardStripDelta(from: event) != nil {
            _ = KeyboardEventHandler.handleScrollWheel(event)
            return
        }
        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !OverlayPanelManager.shared.isAlertActive,
           OverlayPanelManager.shared.keyboardOwner == .favoriteNoteEditor {
            super.keyDown(with: event)
            return
        }

        switch Self.keyRoute(for: event,
                             isSearchActive: OverlayPanelManager.shared.isSearchActive,
                             isAlertActive: OverlayPanelManager.shared.isAlertActive,
                             keyboardOwner: OverlayPanelManager.shared.keyboardOwner) {
        case .cancel:
            routeCancelKey()
        case .cancelFavoriteNoteEditing:
            routeFavoriteNoteCancelKey()
        case .confirmAlert:
            routeAlertConfirmKey()
        case .selectAll:
            routeSelectAllKey()
        case .openSearch:
            routeOpenSearchKey()
        case .consume:
            break
        case .system:
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if !OverlayPanelManager.shared.isAlertActive,
           OverlayPanelManager.shared.keyboardOwner == .favoriteNoteEditor {
            return super.performKeyEquivalent(with: event)
        }

        switch Self.keyRoute(for: event,
                             isSearchActive: OverlayPanelManager.shared.isSearchActive,
                             isAlertActive: OverlayPanelManager.shared.isAlertActive,
                             keyboardOwner: OverlayPanelManager.shared.keyboardOwner) {
        case .cancel:
            routeCancelKey()
            return true
        case .cancelFavoriteNoteEditing:
            routeFavoriteNoteCancelKey()
            return true
        case .confirmAlert:
            routeAlertConfirmKey()
            return true
        case .selectAll:
            routeSelectAllKey()
            return true
        case .openSearch:
            routeOpenSearchKey()
            return true
        case .consume:
            return true
        case .system:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if OverlayPanelManager.shared.isAlertActive {
            routeCancelKey()
            return
        }
        if OverlayPanelManager.shared.keyboardOwner == .favoriteNoteEditor {
            NotificationCenter.default.post(name: .overlayCancelFavoriteNoteEditing, object: nil)
            OverlayPanelManager.shared.noteFavoriteNoteEditingCancelled()
            return
        }
        if OverlayPanelManager.shared.keyboardOwner == .searchField {
            routeCancelKey()
            return
        }
        routeCancelKey()
    }

    enum KeyRoute: Equatable {
        case cancel
        case cancelFavoriteNoteEditing
        case confirmAlert
        case selectAll
        case openSearch
        case consume
        case system
    }

    static func keyRoute(
        keyCode: UInt16,
        chars: String? = nil,
        isSearchActive: Bool,
        isAlertActive: Bool = false,
        modifierFlags: NSEvent.ModifierFlags = [],
        keyboardOwner: OverlayKeyboardOwner = .overlayNavigation
    ) -> KeyRoute {
        if isAlertActive, keyCode == 53 {
            return .cancel
        }

        if isAlertActive {
            if OverlayKeyboardRouter.isAlertConfirmKey(keyCode: keyCode) {
                return .confirmAlert
            }
            return OverlayKeyboardRouter.shouldConsumeAlertKeyDown(keyCode: keyCode) ? .consume : .system
        }

        if keyboardOwner == .favoriteNoteEditor {
            if keyCode == 53 {
                return .cancelFavoriteNoteEditing
            }
            return .system
        }

        if keyCode == 53 {
            return .cancel
        }

        if Self.isSearchShortcut(keyCode: keyCode, modifierFlags: modifierFlags) {
            return .openSearch
        }

        if keyboardOwner == .searchField {
            if keyCode == 48, modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty {
                return .consume
            }
            return .system
        }

        if chars == "/",
           modifierFlags.intersection([.command, .control, .option]).isEmpty {
            return .openSearch
        }

        if keyCode == 0, modifierFlags.contains(.command) {
            return .selectAll
        }

        // ⌘C / ⌘P：导航态消费；搜索框拥有键盘时 ⌘C 已在上方放行给 TextField
        if modifierFlags.contains(.command),
           modifierFlags.intersection([.shift, .option, .control]).isEmpty,
           keyCode == 8 || keyCode == 35 {
            return .consume
        }

        guard !isSearchActive else { return .system }

        // Space / Enter / Delete / 方向键 / ⌘数字
        if keyCode == 49 || keyCode == 36 || keyCode == 51 || keyCode == 117 {
            return .consume
        }
        if modifierFlags.contains(.command), OverlayKeyboardRouter.cmdNumberIndex(keyCode: keyCode) != nil {
            return .consume
        }
        if keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126 {
            return .consume
        }
        // 搜索关闭时忽略普通文本输入，既不自动打开搜索，也不交给 NSPanel 触发系统提示音。
        if !modifierFlags.contains(.command),
           !modifierFlags.contains(.control),
           let first = chars?.first,
           first.isLetter || first.isNumber || first.isSymbol || first.isPunctuation || first.isWhitespace {
            return .consume
        }
        return .system
    }

    static func keyRoute(
        for event: NSEvent,
        isSearchActive: Bool,
        isAlertActive: Bool,
        keyboardOwner: OverlayKeyboardOwner
    ) -> KeyRoute {
        keyRoute(
            keyCode: event.keyCode,
            chars: event.characters,
            isSearchActive: isSearchActive,
            isAlertActive: isAlertActive,
            modifierFlags: event.modifierFlags,
            keyboardOwner: keyboardOwner
        )
    }

    private func routeAlertConfirmKey() {
        NotificationCenter.default.post(name: .overlayAlertConfirm, object: nil)
    }

    private func routeFavoriteNoteCancelKey() {
        NotificationCenter.default.post(name: .overlayCancelFavoriteNoteEditing, object: nil)
        OverlayPanelManager.shared.noteFavoriteNoteEditingCancelled()
    }

    private func routeSelectAllKey() {
        NotificationCenter.default.post(name: .overlaySelectAll, object: nil)
    }

    private func routeOpenSearchKey() {
        NotificationCenter.default.post(name: .overlayOpenSearchImmediate, object: nil)
    }

    private func routeCancelKey() {
        if OverlayPanelManager.shared.isAlertActive {
            NotificationCenter.default.post(name: .overlayAlertCancel, object: nil)
        } else if OverlayPanelManager.shared.isFilterPopoverActive {
            NotificationCenter.default.post(name: .overlayCloseFilter, object: nil)
        } else if QLPreviewHelper.shared.shouldConsumeEscape {
            QLPreviewHelper.shared.dismiss()
        } else if OverlayPanelManager.shared.shouldSwallowOverlayCancel {
            return
        } else if OverlayPanelManager.shared.isSearchActive {
            NotificationCenter.default.post(name: .overlayCloseSearch, object: nil)
        } else {
            NotificationCenter.default.post(name: .overlayRequestDismiss, object: nil)
        }
    }

    private static func isSearchShortcut(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        keyCode == 3 && modifierFlags.contains(.command)
    }
}

// MARK: - 全屏覆盖层面板管理器
final class OverlayPanelManager: @unchecked Sendable {

    private struct PasteShortcutResult {
        let didPost: Bool
        let sourceCreationMilliseconds: Int
        let eventCreationMilliseconds: Int
        let eventPostMilliseconds: Int
    }

    static let shared = OverlayPanelManager()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "overlay")
    private let diagnosticsLog = PastryLogger(category: "overlay")

    /// 粘贴提示音（预加载避免每次读磁盘阻塞主线程）
    private static let pasteSound: NSSound? = {
        guard let path = Bundle.main.path(forResource: "Paste", ofType: "aiff") else { return nil }
        let sound = NSSound(contentsOfFile: path, byReference: true)
        // 预暖音频管线，避免首次 play() 的冷启动延迟
        sound?.play()
        sound?.stop()
        return sound
    }()

    private var panel: ClipboardOverlayPanel?
    private var previousFrontApp: NSRunningApplication?
    private var alertActive = false
    private var isPasting = false
    private var isDragThrough = false
    private var panelResignKeyObserver: NSObjectProtocol?
    /// 关掉预览后 popover.close() 会让面板失焦；短暂忽略 resignKey→hide，避免 Esc 连带关托盘。
    private var suppressResignKeyHideUntil: CFAbsoluteTime = 0
    /// 同一按键可能同时走 monitor / cancelOperation / keyEquivalent；预览关掉后极短吞掉重复 cancel。
    private var swallowOverlayCancelUntil: CFAbsoluteTime = 0
    private lazy var keyboardRouter = OverlayKeyboardRouter(
        isAlertActive: { [weak self] in self?.alertActive ?? false },
        isSearchActive: { [weak self] in self?.isSearchActive ?? false },
        keyboardOwner: { [weak self] in self?.keyboardOwner ?? .overlayNavigation }
    )

    private init() {
        NotificationCenter.default.addObserver(
            forName: .overlayAlertActive, object: nil, queue: .main
        ) { [weak self] note in
            self?.alertActive = (note.userInfo?["active"] as? Bool) ?? false
        }
    }

    // MARK: - 显示/隐藏

    /// 热键触发时刻 — 由 GlobalHotkeyManager 在 Carbon 回调中设置，
    /// showPanel() 读取后清零
    nonisolated(unsafe) static var hotkeyFiredAt: CFAbsoluteTime?

    /// 进程内只预热一次（玻璃材质 / Hosting / 卡片首帧）
    private static var didWarmupPipeline = false

    private static var isPerformanceLoggingEnabled: Bool {
        DeveloperDiagnostics.isEnabled
    }

    /// 性能日志写入（~/Library/Logs/Pastry/perf.log），异步不阻塞热路径
    private static func writePerfLog(_ line: String) {
        DeveloperDiagnostics.writePerfLine(line)
    }

    @MainActor
    func show() {
        guard !isVisible else { return }
        showPanel()
    }

    /// 启动后预热 NSHostingView + 玻璃材质 + 卡片首帧布局，避免用户第一次打开时卡在入场动画中途。
    @MainActor
    func warmupPipelineIfNeeded() {
        guard !Self.didWarmupPipeline else { return }
        Self.didWarmupPipeline = true
        guard !isVisible else { return }

        let t0 = CFAbsoluteTimeGetCurrent()
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                ?? NSScreen.main
                ?? NSScreen.screens.first
        else { return }

        let screenFrame = screen.visibleFrame
        let warmPanel = ClipboardOverlayPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        warmPanel.isOpaque = false
        warmPanel.backgroundColor = .clear
        warmPanel.hasShadow = false
        warmPanel.level = .popUpMenu
        warmPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        warmPanel.isReleasedWhenClosed = false
        warmPanel.ignoresMouseEvents = true
        warmPanel.alphaValue = 0.01
        warmPanel.animationBehavior = .none

        let hostingView = NSHostingView(
            rootView: OverlayView(isPipelineWarmup: true)
                .environmentObject(StoreManager.shared)
        )
        hostingView.frame = screenFrame
        hostingView.autoresizingMask = [.width, .height]
        warmPanel.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        warmPanel.orderFrontRegardless()
        warmPanel.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        warmPanel.orderOut(nil)
        warmPanel.contentView = nil

        if Self.isPerformanceLoggingEnabled {
            let ms = Int(((CFAbsoluteTimeGetCurrent() - t0) * 1000).rounded())
            Self.writePerfLog("\(Date()) | type: warmup | total: \(ms)ms | items: \(StoreManager.shared.items.count)")
        }
        diagnosticsLog.info(
            "覆盖层管线预热完成",
            event: "overlay.warmup.completed",
            metadata: ["item_count": String(StoreManager.shared.items.count)],
            durationMilliseconds: Int(((CFAbsoluteTimeGetCurrent() - t0) * 1_000).rounded())
        )
        log.info("覆盖层管线预热完成")
    }

    @MainActor
    func hide() {
        guard isVisible || isDragThrough else { return }
        cleanup()
        NotificationCenter.default.post(name: .overlayDidHide, object: nil)
        DeveloperDiagnostics.record(DiagnosticsEvent.overlayDismiss)
        diagnosticsLog.info("覆盖层已关闭", event: "overlay.hidden")
        log.info("覆盖层已关闭")
    }

    /// 预览关掉后把 key 夺回托盘，避免下一次 Esc 落到别处。
    func makePanelKey() {
        panel?.makeKey()
    }

    /// Esc/点击关闭预览时调用：popover.close() 触发的 resignKey 不应连带 hide 托盘。
    func notePreviewDismissed() {
        let now = CFAbsoluteTimeGetCurrent()
        suppressResignKeyHideUntil = now + 0.45
        swallowOverlayCancelUntil = now + 0.05
        makePanelKey()
    }

    /// 预览刚被同一 Esc 关掉时，吞掉级联的第二次 cancel（勿关托盘）。
    var shouldSwallowOverlayCancel: Bool {
        CFAbsoluteTimeGetCurrent() < swallowOverlayCancelUntil
    }

    /// Esc 取消备注编辑后：吞掉同一次按键级联的关托盘，并夺回 key。
    func noteFavoriteNoteEditingCancelled() {
        swallowOverlayCancelUntil = CFAbsoluteTimeGetCurrent() + 0.2
        if keyboardOwner == .favoriteNoteEditor {
            keyboardOwner = .overlayNavigation
        }
        makePanelKey()
    }

    /// 失焦是否应保留托盘（预览显示中，或刚关掉预览的宽限期内且 App 仍活跃）。
    static func shouldKeepOverlayAfterResignKey(
        isPreviewShowing: Bool,
        suppressUntil: CFAbsoluteTime,
        now: CFAbsoluteTime,
        appIsActive: Bool
    ) -> Bool {
        guard appIsActive else { return false }
        return isPreviewShowing || now < suppressUntil
    }

    /// Quick Look popover 的兜底锚点（卡片未渲染时用面板 contentView）。
    func previewAnchorView() -> NSView? {
        panel?.contentView
    }

    @MainActor
    func toggle() {
        if isVisible {
            NotificationCenter.default.post(name: .overlayRequestDismiss, object: nil)
        } else {
            show()
        }
    }

    /// 隐藏 + 粘贴到之前的前台应用（点击卡片使用）
    /// 先写剪贴板 + ⌘V，面板隐藏/DB/音效后台收尾，不阻塞粘贴
    @MainActor
    func hideAndPaste(_ item: ClipboardItem) async {
        guard isVisible else { return }

        // 关面板前先要权限：未授权时系统弹窗 + 托盘保持打开（⌘1–9 / Enter / 点击同路径）
        let actionStart = CFAbsoluteTimeGetCurrent()
        guard Self.ensureAccessibilityForPaste() else { return }
        let permissionCheckedAt = CFAbsoluteTimeGetCurrent()

        let t0 = permissionCheckedAt
        let fmt = item.sourceFormat

        isPasting = true
        let targetApp = previousFrontApp
        previousFrontApp = nil

        // 1. 挂起监听，防止读到自己的写入
        ClipboardMonitor.shared.suspend()

        // 2. 先激活目标 App + 隐藏面板，避免完整内容或图片读取让面板退场慢一拍。
        closePanelForPaste(targetApp: targetApp)
        let t1 = CFAbsoluteTimeGetCurrent()

        // 3. 写剪贴板（文本/文件立即，图片 I/O 后台完成）
        let result = await PasteboardWriter.write(item, options: .overlaySingle)
        ClipboardMonitor.shared.ignoreCurrentChange()
        let t2 = CFAbsoluteTimeGetCurrent()
        guard result == .written else {
            // 文件全部缺失或图片读取失败时，静默取消粘贴。
            diagnosticsLog.warning(
                "写入剪贴板失败，取消粘贴",
                event: "paste.single.clipboard_write_failed",
                metadata: ["source_format": fmt.rawValue]
            )
            ClipboardMonitor.shared.resume()
            isPasting = false
            return
        }

        // 4. ⌘V（面板已隐藏，目标 App 在前台）
        let pasteShortcut = Self.simulatePaste()
        if pasteShortcut.didPost {
            SoundFeedback.play(Self.pasteSound)
        }
        let t3 = CFAbsoluteTimeGetCurrent()

        // 5. 后台收尾：DB / 恢复监听 / 刷新
        DatabaseManager.shared.bumpTimestamp(id: item.id.uuidString)
        DatabaseManager.shared.incrementDisplayCount(id: item.id.uuidString)
        ClipboardMonitor.shared.resume()
        StoreManager.shared.refresh()
        isPasting = false
        DeveloperDiagnostics.record(DiagnosticsEvent.pasteSingle)
        diagnosticsLog.info(
            "单条粘贴完成",
            event: "paste.single.completed",
            metadata: [
                "source_format": fmt.rawValue,
                "event_posted": String(pasteShortcut.didPost)
            ],
            durationMilliseconds: Int(((t3 - actionStart) * 1_000).rounded())
        )

        if Self.isPerformanceLoggingEnabled {
            let ms = { (d: CFAbsoluteTime) in Int((d * 1000).rounded()) }
            let perfLine = "\(Date()) | type: paste | sourceFormat: \(fmt) | accessibilityCheck: \(ms(permissionCheckedAt-actionStart))ms | closePanel: \(ms(t1-t0))ms | clipboardWrite: \(ms(t2-t1))ms | simulatePaste: \(ms(t3-t2))ms | eventSource: \(pasteShortcut.sourceCreationMilliseconds)ms | eventCreate: \(pasteShortcut.eventCreationMilliseconds)ms | eventPost: \(pasteShortcut.eventPostMilliseconds)ms | total: \(ms(t3-actionStart))ms"
            log.info("⏱ \(perfLine, privacy: .public)")
            Self.writePerfLog(perfLine)
        }
    }

    /// 多选粘贴：将所有选中条目的文本拼接后一次性 ⌘V
    @MainActor
    func hideAndPasteMultiple(_ items: [ClipboardItem]) {
        guard isVisible, !items.isEmpty else { return }

        let actionStart = CFAbsoluteTimeGetCurrent()
        guard Self.ensureAccessibilityForPaste() else { return }
        let permissionCheckedAt = CFAbsoluteTimeGetCurrent()

        let t0 = permissionCheckedAt

        isPasting = true
        let targetApp = previousFrontApp
        previousFrontApp = nil

        ClipboardMonitor.shared.suspend()

        // 先关闭面板，避免收集完整内容时视觉上慢一拍。
        closePanelForPaste(targetApp: targetApp)
        let t1 = CFAbsoluteTimeGetCurrent()

        // 收集所有文本内容（文本类 + 文件路径），用换行拼接
        let lines = items.compactMap { item -> String? in
            switch item.sourceFormat {
            case .text, .rtf, .html:
                return DatabaseManager.shared.loadFullContent(id: item.id) ?? item.content
            case .fileURL:
                return item.content  // 文件路径也是文本
            case .image:
                return nil  // 跳过多选的图片
            }
        }
        let combined = lines.joined(separator: "\n")
        PasteboardWriter.writePlainText(combined)
        ClipboardMonitor.shared.ignoreCurrentChange()
        let t2 = CFAbsoluteTimeGetCurrent()

        // ⌘V
        let pasteShortcut = Self.simulatePaste()
        if pasteShortcut.didPost {
            SoundFeedback.play(Self.pasteSound)
        }
        let t3 = CFAbsoluteTimeGetCurrent()

        // 后台收尾：每个条目更新 DB
        for item in items {
            DatabaseManager.shared.bumpTimestamp(id: item.id.uuidString)
            DatabaseManager.shared.incrementDisplayCount(id: item.id.uuidString)
        }
        ClipboardMonitor.shared.resume()
        StoreManager.shared.refresh()
        isPasting = false
        DeveloperDiagnostics.record(DiagnosticsEvent.pasteMulti)
        diagnosticsLog.info(
            "多选粘贴完成",
            event: "paste.multi.completed",
            metadata: [
                "item_count": String(items.count),
                "text_item_count": String(lines.count),
                "event_posted": String(pasteShortcut.didPost)
            ],
            durationMilliseconds: Int(((t3 - actionStart) * 1_000).rounded())
        )

        if Self.isPerformanceLoggingEnabled {
            let ms = { (d: CFAbsoluteTime) in Int((d * 1000).rounded()) }
            let perfLine = "\(Date()) | type: pasteMulti | itemCount: \(items.count) | accessibilityCheck: \(ms(permissionCheckedAt-actionStart))ms | closePanel: \(ms(t1-t0))ms | writeText: \(ms(t2-t1))ms | simulatePaste: \(ms(t3-t2))ms | eventSource: \(pasteShortcut.sourceCreationMilliseconds)ms | eventCreate: \(pasteShortcut.eventCreationMilliseconds)ms | eventPost: \(pasteShortcut.eventPostMilliseconds)ms | total: \(ms(t3-actionStart))ms"
            log.info("⏱ \(perfLine, privacy: .public)")
            Self.writePerfLog(perfLine)
        }
    }

    /// 拖拽开始时临时透传鼠标事件，让拖拽能到达目标应用
    @MainActor
    func beginDragThrough() {
        panel?.ignoresMouseEvents = true
        isDragThrough = true
        panel?.orderOut(nil)   // 拖拽开始即收起面板
        // 轮询鼠标释放来触发清理
        DispatchQueue.main.async { [weak self] in
            self?.pollDragEnd()
        }
    }

    /// 轮询鼠标按键状态，释放时关闭面板
    @MainActor
    private func pollDragEnd() {
        guard isDragThrough else { return }
        if NSEvent.pressedMouseButtons == 0 {
            // 鼠标已释放 → 拖拽完成，直接关闭
            hide()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.pollDragEnd()
            }
        }
    }

    @MainActor
    private func closePanelForPaste(targetApp: NSRunningApplication?) {
        targetApp?.activate()
        cleanup()
        NotificationCenter.default.post(name: .overlayDidHide, object: nil)
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// 搜索栏是否展开 — ESC 优先级判断
    var isSearchActive = false

    /// 筛选气泡是否展开 — ESC 优先关闭气泡，不关托盘
    var isFilterPopoverActive = false

    /// 托盘是否为横向卡片布局（侧滚轮 → 横向卡带）
    /// ⚠️ 仅主线程读写。
    var isHorizontalCardLayout = true

    /// 当前键盘事件归属。只有 overlayNavigation 会执行卡片级快捷键。
    /// ⚠️ 必须只在主线程读写（无锁/actor 保护，放任何非主线程访问即 data race）。
    var keyboardOwner: OverlayKeyboardOwner = .overlayNavigation

    /// 删除确认弹窗是否活跃 — Esc 放行给系统弹窗处理
    var isAlertActive: Bool { alertActive }

    // MARK: - 私有

    @MainActor
    private func showPanel() {
        let t0 = CFAbsoluteTimeGetCurrent()

        // 若有快捷键触发时刻，预取并计算调用链延迟
        let hotkeyAt = Self.hotkeyFiredAt
        let hotkeyDispatchMs: Int? = hotkeyAt.map { hotkey in
            Int(((t0 - hotkey) * 1000).rounded())
        }

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first else {
            diagnosticsLog.error("无法获取显示器", event: "overlay.show.no_screen")
            log.error("无法获取屏幕")
            return
        }

        previousFrontApp = NSWorkspace.shared.frontmostApplication

        let screenFrame = screen.visibleFrame  // 不含菜单栏，保留菜单栏交互

        let activePanel: ClipboardOverlayPanel
        let reusedPanel: Bool
        let t1: CFAbsoluteTime
        let t2: CFAbsoluteTime
        let t2a: CFAbsoluteTime
        let t3: CFAbsoluteTime

        if let existingPanel = panel {
            reusedPanel = true
            activePanel = existingPanel
            existingPanel.setFrame(screenFrame, display: false)
            existingPanel.contentView?.frame = NSRect(origin: .zero, size: screenFrame.size)
            existingPanel.ignoresMouseEvents = false
            t1 = CFAbsoluteTimeGetCurrent()
            t2 = t1
            t2a = t1
            NotificationCenter.default.post(name: .overlayWillShow, object: nil)
            existingPanel.contentView?.layoutSubtreeIfNeeded()
            t3 = CFAbsoluteTimeGetCurrent()
        } else {
            reusedPanel = false
            let newPanel = ClipboardOverlayPanel(
                contentRect: screenFrame,
                styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = false
            newPanel.level = .popUpMenu
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.isReleasedWhenClosed = false
            newPanel.ignoresMouseEvents = false
            newPanel.acceptsMouseMovedEvents = true
            newPanel.hidesOnDeactivate = false
            newPanel.animationBehavior = .none
            t1 = CFAbsoluteTimeGetCurrent()

            let overlayView = OverlayView()
                .environmentObject(StoreManager.shared)
            t2 = CFAbsoluteTimeGetCurrent()

            let hostingView = NSHostingView(rootView: overlayView)
            t2a = CFAbsoluteTimeGetCurrent()

            hostingView.frame = NSRect(origin: .zero, size: screenFrame.size)
            hostingView.autoresizingMask = [.width, .height]
            newPanel.contentView = hostingView
            panel = newPanel
            activePanel = newPanel
            t3 = CFAbsoluteTimeGetCurrent()
        }

        activePanel.orderFrontRegardless()
        activePanel.makeKey()

        let t4 = CFAbsoluteTimeGetCurrent()

        if Self.isPerformanceLoggingEnabled {
            // 性能日志（OSLog + 文件持久化）
            let ms = { (d: CFAbsoluteTime) in Int((d * 1000).rounded()) }
            let itemCount = StoreManager.shared.items.count
            let maxLen = StoreManager.shared.items.map { $0.content.count }.max() ?? 0
            let totalLen = StoreManager.shared.items.reduce(0) { $0 + $1.content.count }

            var perfLine = "\(Date()) | type: panel | items: \(itemCount) | maxContent: \(maxLen) | totalContent: \(totalLen)"
            if let dispatchMs = hotkeyDispatchMs {
                perfLine += " | hotkeyDispatch: \(dispatchMs)ms"
            }
            perfLine += " | reused: \(reusedPanel) | panelInit: \(ms(t1-t0))ms | overlayView: \(ms(t2-t1))ms | hostingInit: \(ms(t2a-t2))ms | hostingLayout: \(ms(t3-t2a))ms | orderFront: \(ms(t4-t3))ms | total: \(ms(t4-t0))ms"

            log.info("⏱ \(perfLine, privacy: .public)")
            Self.writePerfLog(perfLine)
        }
        Self.hotkeyFiredAt = nil

        // 面板失焦（Cmd+Tab / 点其他 App）→ 自动收起（拖拽穿透 / 预览关合抢焦点除外）
        panelResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: activePanel, queue: .main
        ) { [weak self] _ in
            guard let self, !self.isPasting, !self.alertActive, !self.isDragThrough else { return }
            DispatchQueue.main.async {
                if Self.shouldKeepOverlayAfterResignKey(
                    isPreviewShowing: QLPreviewHelper.shared.isShowing,
                    suppressUntil: self.suppressResignKeyHideUntil,
                    now: CFAbsoluteTimeGetCurrent(),
                    appIsActive: NSApp.isActive
                ) {
                    self.panel?.makeKey()
                    return
                }
                if QLPreviewHelper.shared.isShowing {
                    QLPreviewHelper.shared.dismiss()
                }
                self.diagnosticsLog.info(
                    "覆盖层因失去焦点关闭",
                    event: "overlay.resign_key.hidden",
                    metadata: ["application_active": String(NSApp.isActive)]
                )
                self.hide()
            }
        }

        DeveloperDiagnostics.record(DiagnosticsEvent.overlayOpen)
        installKeyboardMonitor()
        diagnosticsLog.info(
            "覆盖层已显示",
            event: "overlay.show.completed",
            metadata: [
                "item_count": String(StoreManager.shared.items.count),
                "layout": isHorizontalCardLayout ? "horizontal" : "vertical",
                "reused": String(reusedPanel)
            ],
            durationMilliseconds: Int(((t4 - t0) * 1_000).rounded())
        )

        log.info("覆盖层已显示")
    }

    private func cleanup() {
        if let observer = panelResignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            panelResignKeyObserver = nil
        }
        removeKeyboardMonitor()
        QLPreviewHelper.shared.dismiss()
        suppressResignKeyHideUntil = 0
        swallowOverlayCancelUntil = 0
        isDragThrough = false
        panel?.ignoresMouseEvents = false
        panel?.orderOut(nil)
        previousFrontApp = nil
        isSearchActive = false
        isFilterPopoverActive = false
        keyboardOwner = .overlayNavigation
    }

    // MARK: - 键盘事件拦截

    private func installKeyboardMonitor() {
        keyboardRouter.install()
    }

    static func cmdNumberIndex(keyCode: UInt16) -> Int? {
        OverlayKeyboardRouter.cmdNumberIndex(keyCode: keyCode)
    }

    static func shouldAllowEnterForIME() -> Bool {
        OverlayKeyboardRouter.shouldAllowEnterForIME()
    }

    private func removeKeyboardMonitor() {
        keyboardRouter.remove()
    }

    // MARK: - ⌘V 模拟

    /// 粘贴前权限闸门：未授权则触发系统申请弹窗，并通知托盘刷新 banner。
    /// - Returns: 是否可继续粘贴（已授权）。
    @discardableResult
    static func ensureAccessibilityForPaste() -> Bool {
        if AccessibilityPermissionChecker.shared.requestTrustedForPaste() {
            return true
        }
        Logger(subsystem: "com.nekutai.pastry", category: "paste")
            .warning("粘贴中止：缺少辅助功能权限（已触发系统授权请求）")
        NotificationCenter.default.post(name: .overlayAccessibilityDenied, object: nil)
        DeveloperDiagnostics.record(DiagnosticsEvent.accessibilityDenied)
        return false
    }

    /// 调用方必须先通过 `ensureAccessibilityForPaste()`；避免在同一次粘贴中
    /// 连续执行两次可能阻塞的 AX 权限查询。
    private static func simulatePaste() -> PasteShortcutResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let milliseconds = { (start: CFAbsoluteTime, end: CFAbsoluteTime) in
            Int(((end - start) * 1_000).rounded())
        }
        let vKey = CGKeyCode(9)
        guard let source = CGEventSource(stateID: .privateState) else {
            let failedAt = CFAbsoluteTimeGetCurrent()
            Logger(subsystem: "com.nekutai.pastry", category: "paste").warning("CGEventSource 创建失败 — 可能缺少辅助功能权限")
            NotificationCenter.default.post(name: .overlayAccessibilityDenied, object: nil)
            DeveloperDiagnostics.record(DiagnosticsEvent.accessibilityDenied)
            return PasteShortcutResult(
                didPost: false,
                sourceCreationMilliseconds: milliseconds(startedAt, failedAt),
                eventCreationMilliseconds: 0,
                eventPostMilliseconds: 0
            )
        }
        let sourceCreatedAt = CFAbsoluteTimeGetCurrent()

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            let failedAt = CFAbsoluteTimeGetCurrent()
            return PasteShortcutResult(
                didPost: false,
                sourceCreationMilliseconds: milliseconds(startedAt, sourceCreatedAt),
                eventCreationMilliseconds: milliseconds(sourceCreatedAt, failedAt),
                eventPostMilliseconds: 0
            )
        }
        let eventsCreatedAt = CFAbsoluteTimeGetCurrent()

        cmdDown.flags = .maskCommand
        cmdUp.flags = .maskCommand

        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        cmdDown.postToPid(pid)
        cmdUp.postToPid(pid)
        let postedAt = CFAbsoluteTimeGetCurrent()
        return PasteShortcutResult(
            didPost: true,
            sourceCreationMilliseconds: milliseconds(startedAt, sourceCreatedAt),
            eventCreationMilliseconds: milliseconds(sourceCreatedAt, eventsCreatedAt),
            eventPostMilliseconds: milliseconds(eventsCreatedAt, postedAt)
        )
    }

    deinit {
        removeKeyboardMonitor()
    }
}
