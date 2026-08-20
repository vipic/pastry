import Cocoa

enum OverlayKeyboardOwner: Equatable {
    case overlayNavigation
    case searchField
    case favoriteNoteEditor
}

final class OverlayKeyboardRouter {
    private var keyboardMonitor: Any?
    private var flagsChangedMonitor: Any?
    private var cmdWasDown = false

    private let isAlertActive: () -> Bool
    private let isSearchActive: () -> Bool
    private let keyboardOwner: () -> OverlayKeyboardOwner

    init(
        isAlertActive: @escaping () -> Bool,
        isSearchActive: @escaping () -> Bool,
        keyboardOwner: @escaping () -> OverlayKeyboardOwner
    ) {
        self.isAlertActive = isAlertActive
        self.isSearchActive = isSearchActive
        self.keyboardOwner = keyboardOwner
    }

    func install() {
        remove()

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }

        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event) ?? event
        }
    }

    func remove() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
        cmdWasDown = false
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let owner = keyboardOwner()

        // Esc：筛选气泡 → 预览 popover → 搜索栏 → 关闭面板（逐层收起）
        if event.keyCode == 53 {
            if isAlertActive() {
                NotificationCenter.default.post(name: .overlayAlertCancel, object: nil)
                return nil
            }
            if owner == .favoriteNoteEditor
                || Self.shouldCancelFavoriteNoteEditingOnEscape(
                    owner: owner,
                    isSearchActive: isSearchActive(),
                    textInputFocused: Self.isTextInputFocused()
                )
            {
                NotificationCenter.default.post(name: .overlayCancelFavoriteNoteEditing, object: nil)
                OverlayPanelManager.shared.noteFavoriteNoteEditingCancelled()
                return nil
            }
            if OverlayPanelManager.shared.isFilterPopoverActive {
                NotificationCenter.default.post(name: .overlayCloseFilter, object: nil)
                return nil
            }
            if QLPreviewHelper.shared.shouldConsumeEscape {
                QLPreviewHelper.shared.dismiss()
                return nil
            }
            if OverlayPanelManager.shared.shouldSwallowOverlayCancel {
                return nil
            }
            if isSearchActive() {
                NotificationCenter.default.post(name: .overlayCloseSearch, object: nil)
                return nil
            }
            NotificationCenter.default.post(name: .overlayRequestDismiss, object: nil)
            return nil
        }

        // 弹窗活跃：仅消费 Delete，Enter 与 Tab 交给当前焦点控件（Esc 已在上方处理）。
        if isAlertActive() {
            if Self.shouldConsumeAlertKeyDown(keyCode: event.keyCode) {
                return nil
            }
            return event
        }

        if owner == .favoriteNoteEditor {
            return event
        }

        if owner == .searchField {
            // 搜索时 Tab 将键盘焦点交给结果卡片；卡片间移动由左右箭头负责。
            if event.keyCode == 48,
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                NotificationCenter.default.post(name: .overlayFocusCards, object: nil)
                return nil
            }
            // 其余文本编辑快捷键都交给系统；只有面板级的 ⌘F 仍由 overlay 管理。
            if event.keyCode == 3, event.modifierFlags.contains(.command) {
                return nil
            }
            return event
        }

        // ⌘F 搜索
        if event.keyCode == 3, event.modifierFlags.contains(.command) {
            if !isSearchActive() {
                NotificationCenter.default.post(name: .overlayOpenSearch, object: nil)
            }
            return nil
        }

        // / 搜索：仅导航态触发；搜索框和备注编辑器拥有键盘时已在上方放行文本输入。
        if event.characters == "/",
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            NotificationCenter.default.post(name: .overlayOpenSearchImmediate, object: nil)
            return nil
        }

        // ⌘A 全选卡片；文本输入拥有键盘时已在上方放行。
        if event.keyCode == 0, event.modifierFlags.contains(.command) {
            NotificationCenter.default.post(name: .overlaySelectAll, object: nil)
            return nil
        }

        // ⌘C 复制选中（不关闭面板）
        if event.keyCode == 8, event.modifierFlags.contains(.command),
           event.modifierFlags.intersection([.shift, .option, .control]).isEmpty {
            NotificationCenter.default.post(name: .overlayCopySelected, object: nil)
            return nil
        }

        // ⌘P 切换收藏
        if event.keyCode == 35, event.modifierFlags.contains(.command),
           event.modifierFlags.intersection([.shift, .option, .control]).isEmpty {
            NotificationCenter.default.post(name: .overlayToggleFavorite, object: nil)
            return nil
        }

        // Space 预览光标项（不进搜索；搜索框拥有键盘时已在上方放行）
        if event.keyCode == 49,
           event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty {
            NotificationCenter.default.post(name: .overlayPreviewCursor, object: nil)
            return nil
        }

        // Delete / Forward Delete — 若焦点在文本输入框则放行
        if event.keyCode == 51 || event.keyCode == 117 {
            if Self.isTextInputFocused() { return event }
            NotificationCenter.default.post(name: .overlayDeleteSelected, object: nil)
            return nil
        }

        let extend = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 126: // 上
            if isSearchActive() { return event }
            postCursorMove(delta: -1, extend: extend)
            return nil
        case 125: // 下
            if isSearchActive() { return event }
            postCursorMove(delta: 1, extend: extend)
            return nil
        case 123: // 左
            postCursorMove(delta: -1, extend: extend)
            return nil
        case 124: // 右
            postCursorMove(delta: 1, extend: extend)
            return nil
        case 115: // Home
            if isSearchActive() { return event }
            postCursorMove(target: "home", extend: extend)
            return nil
        case 119: // End
            if isSearchActive() { return event }
            postCursorMove(target: "end", extend: extend)
            return nil
        case 116: // Page Up
            if isSearchActive() { return event }
            postCursorMove(pageDelta: -1, extend: extend)
            return nil
        case 121: // Page Down
            if isSearchActive() { return event }
            postCursorMove(pageDelta: 1, extend: extend)
            return nil
        case 36: // Enter
            if Self.shouldAllowEnterForIME() {
                return event
            }
            if isSearchActive() {
                NotificationCenter.default.post(name: .overlaySearchEnterPaste, object: nil)
                return nil
            }
            NotificationCenter.default.post(name: .overlayConfirmPaste, object: nil)
            return nil
        case let kc where event.modifierFlags.contains(.command):
            if let idx = Self.cmdNumberIndex(keyCode: kc) {
                NotificationCenter.default.post(name: .overlayCmdPaste, object: nil,
                                                userInfo: ["index": idx])
                return nil
            }
            fallthrough
        default:
            if isSearchActive() {
                return event
            }
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent {
        let shouldShowCmdBadges = event.modifierFlags.contains(.command)
            && keyboardOwner() == .overlayNavigation
        if shouldShowCmdBadges != cmdWasDown {
            cmdWasDown = shouldShowCmdBadges
            NotificationCenter.default.post(name: .overlayCmdStateChanged, object: nil,
                                            userInfo: ["cmdDown": shouldShowCmdBadges])
        }
        return event
    }

    private func postCursorMove(delta: Int? = nil, pageDelta: Int? = nil, target: String? = nil, extend: Bool) {
        var userInfo: [String: Any] = ["extend": extend]
        if let delta { userInfo["delta"] = delta }
        if let pageDelta { userInfo["pageDelta"] = pageDelta }
        if let target { userInfo["target"] = target }
        NotificationCenter.default.post(name: .overlayMoveCursor, object: nil, userInfo: userInfo)
    }

    private static let cmdNumberMap: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
    ]

    static func cmdNumberIndex(keyCode: UInt16) -> Int? {
        cmdNumberMap[keyCode]
    }

    static func shouldConsumeAlertKeyDown(keyCode: UInt16) -> Bool {
        keyCode == 51 || keyCode == 117
    }

    /// 检查当前焦点是否在文本输入框内（搜索框等）
    static func isTextInputFocused() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder.isKind(of: NSTextView.self) { return true }
        if responder.isKind(of: NSTextField.self) { return true }
        if responder.isKind(of: NSSearchField.self) { return true }
        return false
    }

    /// Esc 应取消场景备注编辑（含 owner 尚未同步、但输入框已聚焦的情况）。
    static func shouldCancelFavoriteNoteEditingOnEscape(
        owner: OverlayKeyboardOwner,
        isSearchActive: Bool,
        textInputFocused: Bool
    ) -> Bool {
        if owner == .favoriteNoteEditor { return true }
        // 备注 TextField 已聚焦，但 keyboardOwner 尚未切到 favoriteNoteEditor
        return textInputFocused && !isSearchActive && owner != .searchField
    }

    /// 当前输入框是否有 IME 正在拼写（中文拼音等）。
    /// Enter 键在 marked text 期间应放行给输入法确认上屏，不应被面板拦截。
    static func shouldAllowEnterForIME() -> Bool {
        guard NSApp != nil,
              let window = NSApp.keyWindow,
              let fr = window.firstResponder as? NSTextView else { return false }
        return fr.hasMarkedText()
    }

    deinit {
        remove()
    }
}
