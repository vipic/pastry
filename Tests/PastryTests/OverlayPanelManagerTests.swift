import XCTest
@testable import Pastry

// MARK: - OverlayPanelManager 测试套件
// 测试面板键盘路由与关闭逻辑

final class OverlayPanelManagerTests: XCTestCase {

    // MARK: - 标准焦点导航

    func testTabAndShiftTabRouteAccordingToKeyboardOwner() {
        for owner in [OverlayKeyboardOwner.overlayNavigation, .searchField] {
            let expected: ClipboardOverlayPanel.KeyRoute = owner == .searchField ? .consume : .system
            XCTAssertEqual(
                ClipboardOverlayPanel.keyRoute(
                    keyCode: 48,
                    isSearchActive: owner == .searchField,
                    keyboardOwner: owner
                ),
                expected
            )
            XCTAssertEqual(
                ClipboardOverlayPanel.keyRoute(
                    keyCode: 48,
                    isSearchActive: owner == .searchField,
                    modifierFlags: .shift,
                    keyboardOwner: owner
                ),
                expected
            )
        }
    }

    /// 筛选气泡状态默认关闭，可读写供 Esc 分层收起使用
    func testFilterPopoverActiveFlagDefaultsAndTracks() {
        let manager = OverlayPanelManager.shared
        let previous = manager.isFilterPopoverActive
        defer { manager.isFilterPopoverActive = previous }

        manager.isFilterPopoverActive = false
        XCTAssertFalse(manager.isFilterPopoverActive)

        manager.isFilterPopoverActive = true
        XCTAssertTrue(manager.isFilterPopoverActive)

        manager.isFilterPopoverActive = false
        XCTAssertFalse(manager.isFilterPopoverActive)
    }

    func testAlertConsumesDeleteKeysWithoutSystemBeep() {
        XCTAssertTrue(OverlayKeyboardRouter.shouldConsumeAlertKeyDown(keyCode: 51))
        XCTAssertTrue(OverlayKeyboardRouter.shouldConsumeAlertKeyDown(keyCode: 117))
        XCTAssertFalse(OverlayKeyboardRouter.shouldConsumeAlertKeyDown(keyCode: 36))
        XCTAssertFalse(OverlayKeyboardRouter.shouldConsumeAlertKeyDown(keyCode: 0))
    }

    // MARK: - ⌘+数字快捷键映射

    func testCmdNumberIndexMapping() {
        // keyCode 18 = 1, 19 = 2, ..., 25 = 9
        let pairs: [(UInt16, Int)] = [
            (18, 1), (19, 2), (20, 3), (21, 4),
            (23, 5), (22, 6), (26, 7), (28, 8), (25, 9)
        ]
        for (keyCode, expected) in pairs {
            XCTAssertEqual(OverlayPanelManager.cmdNumberIndex(keyCode: keyCode), expected,
                           "keyCode \(keyCode) should map to index \(expected)")
        }
    }

    func testCmdNumberIndexInvalidKeys() {
        // 非数字键返回 nil
        XCTAssertNil(OverlayPanelManager.cmdNumberIndex(keyCode: 0))   // A
        XCTAssertNil(OverlayPanelManager.cmdNumberIndex(keyCode: 36))  // Enter
        XCTAssertNil(OverlayPanelManager.cmdNumberIndex(keyCode: 53))  // Esc
        XCTAssertNil(OverlayPanelManager.cmdNumberIndex(keyCode: 48))  // Tab
    }

    // MARK: - IME 拼写时 Enter 放行（中文拼音按回车确认英文上屏）


    /// 无 NSTextView 焦点时应返回 false（不拦截 Enter）
    func testShouldAllowEnterForIMEWithoutTextViewFocus() {
        // 单元测试环境无 keyWindow → firstResponder 为 nil → false
        XCTAssertFalse(OverlayPanelManager.shouldAllowEnterForIME())
    }

    // MARK: - 面板默认响铃抑制

    func testOverlayPanelSilentlyConsumesArrowKeysWhenSearchInactive() {
        for keyCode in [UInt16(123), UInt16(124), UInt16(125), UInt16(126)] {
            XCTAssertEqual(
                ClipboardOverlayPanel.keyRoute(
                    keyCode: keyCode,
                    isSearchActive: false
                ),
                .consume
            )
        }
    }

    func testOverlayPanelSilentlyConsumesHandledActionKeysWhenSearchInactive() {
        for keyCode in [UInt16(36), UInt16(51), UInt16(117)] {
            XCTAssertEqual(
                ClipboardOverlayPanel.keyRoute(
                    keyCode: keyCode,
                    isSearchActive: false
                ),
                .consume
            )
        }
    }

    func testOverlayPanelLeavesAlertEnterToFocusedControlAndConsumesDelete() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 36,
                isSearchActive: false,
                isAlertActive: true
            ),
            .system
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 51,
                isSearchActive: false,
                isAlertActive: true
            ),
            .consume
        )
    }

    func testOverlayPanelRoutesCommandAToSelectAllWhenAlertInactive() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 0,
                isSearchActive: false,
                isAlertActive: false,
                modifierFlags: .command
            ),
            .selectAll
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 0,
                isSearchActive: false,
                isAlertActive: true,
                modifierFlags: .command
            ),
            .system
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 0,
                isSearchActive: false,
                isAlertActive: false,
                modifierFlags: []
            ),
            .system
        )
    }

    func testOverlayPanelDoesNotRouteCardCommandsWhenSearchFieldOwnsKeyboard() {
        let textEditingKeys: [(UInt16, NSEvent.ModifierFlags)] = [
            (0, .command),    // ⌘A selects search text
            (36, []),         // Enter stays in search field
            (51, []),         // Delete edits search text
            (117, []),        // Forward delete edits search text
            (123, []),        // Arrow keys move caret
            (124, []),
            (125, []),
            (126, []),
            (18, .command)    // ⌘1 does not quick-paste while typing search
        ]

        for (keyCode, modifiers) in textEditingKeys {
            XCTAssertEqual(
                ClipboardOverlayPanel.keyRoute(
                    keyCode: keyCode,
                    isSearchActive: true,
                    modifierFlags: modifiers,
                    keyboardOwner: .searchField
                ),
                .system,
                "keyCode \(keyCode) should stay with search field"
            )
        }
    }

    func testOverlayPanelKeepsSearchOwnedCommandsScopedToSearch() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 53,
                isSearchActive: true,
                keyboardOwner: .searchField
            ),
            .cancel
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 48,
                isSearchActive: true,
                keyboardOwner: .searchField
            ),
            .consume
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 48,
                isSearchActive: true,
                modifierFlags: .shift,
                keyboardOwner: .searchField
            ),
            .consume
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 3,
                isSearchActive: true,
                modifierFlags: .command,
                keyboardOwner: .searchField
            ),
            .openSearch
        )
    }

    func testOverlayPanelRoutesCommandFToOpenSearchWithoutSystemBeep() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 3,
                isSearchActive: false,
                modifierFlags: .command
            ),
            .openSearch
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 3,
                isSearchActive: true,
                modifierFlags: .command,
                keyboardOwner: .searchField
            ),
            .openSearch
        )
    }

    func testOverlayPanelRoutesSlashToOpenSearchOnlyWhileNavigating() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 44,
                chars: "/",
                isSearchActive: false
            ),
            .openSearch
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 44,
                chars: "/",
                isSearchActive: true,
                keyboardOwner: .searchField
            ),
            .system,
            "搜索框已有焦点时，斜杠应作为查询内容输入"
        )
    }

    func testOverlayPanelDoesNotRouteCardCommandsWhenFavoriteNoteOwnsKeyboard() {
        let noteEditingKeys: [(UInt16, NSEvent.ModifierFlags)] = [
            (0, .command),    // ⌘A selects note text
            (36, []),         // Enter is handled by note editor submit
            (51, []),         // Delete edits note text
            (117, []),
            (123, []),
            (124, []),
            (125, []),
            (126, []),
            (18, .command)
        ]

        for (keyCode, modifiers) in noteEditingKeys {
            XCTAssertEqual(
                ClipboardOverlayPanel.keyRoute(
                    keyCode: keyCode,
                    isSearchActive: false,
                    modifierFlags: modifiers,
                    keyboardOwner: .favoriteNoteEditor
                ),
                .system,
                "keyCode \(keyCode) should stay with favorite note editor"
            )
        }
    }

    func testOverlayPanelRoutesFavoriteNoteEscapeToSilentCancel() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 53,
                isSearchActive: false,
                keyboardOwner: .favoriteNoteEditor
            ),
            .cancelFavoriteNoteEditing
        )
    }

    func testEscapeCancelsFavoriteNoteWhenTextFieldFocusedEvenIfOwnerStale() {
        XCTAssertTrue(
            OverlayKeyboardRouter.shouldCancelFavoriteNoteEditingOnEscape(
                owner: .overlayNavigation,
                isSearchActive: false,
                textInputFocused: true
            )
        )
        XCTAssertFalse(
            OverlayKeyboardRouter.shouldCancelFavoriteNoteEditingOnEscape(
                owner: .searchField,
                isSearchActive: true,
                textInputFocused: true
            )
        )
        XCTAssertFalse(
            OverlayKeyboardRouter.shouldCancelFavoriteNoteEditingOnEscape(
                owner: .overlayNavigation,
                isSearchActive: false,
                textInputFocused: false
            )
        )
    }

    func testOverlayPanelSilentlyIgnoresPrintableKeysWhenSearchIsClosed() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 0,
                chars: "a",
                isSearchActive: false
            ),
            .consume
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 1,
                chars: "搜",
                isSearchActive: false
            ),
            .consume
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 0,
                chars: "a",
                isSearchActive: false,
                modifierFlags: .command
            ),
            .selectAll
        )
    }

    func testOverlayPanelAlertOverridesLocalKeyboardOwner() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 53,
                isSearchActive: false,
                isAlertActive: true,
                keyboardOwner: .favoriteNoteEditor
            ),
            .cancel
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 36,
                isSearchActive: false,
                isAlertActive: true,
                keyboardOwner: .favoriteNoteEditor
            ),
            .system
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 51,
                isSearchActive: false,
                isAlertActive: true,
                keyboardOwner: .searchField
            ),
            .consume
        )
    }

    func testOverlayPanelSilentlyConsumesCommandNumberKeysWhenSearchInactive() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 18,
                isSearchActive: false,
                modifierFlags: .command
            ),
            .consume
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 18,
                isSearchActive: false,
                modifierFlags: []
            ),
            .system
        )
    }

    func testOverlayPanelLeavesArrowKeysWithSearchFieldWhileTyping() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 123,
                isSearchActive: true,
                keyboardOwner: .searchField
            ),
            .system
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 124,
                isSearchActive: true,
                keyboardOwner: .searchField
            ),
            .system
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 36,
                isSearchActive: true,
                keyboardOwner: .searchField
            ),
            .system
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 18,
                isSearchActive: true,
                modifierFlags: .command,
                keyboardOwner: .searchField
            ),
            .system
        )
    }

    func testOverlayPanelConsumesHorizontalArrowsWhenSearchCardsOwnFocus() {
        for keyCode in [UInt16(123), UInt16(124)] {
            XCTAssertEqual(
                ClipboardOverlayPanel.keyRoute(
                    keyCode: keyCode,
                    isSearchActive: true,
                    keyboardOwner: .overlayNavigation
                ),
                .consume
            )
        }
    }

    func testOverlayPanelHandlesEscapeRegardlessOfAlertState() {
        for alertActive in [false, true] {
            XCTAssertEqual(
                ClipboardOverlayPanel.keyRoute(
                    keyCode: 53,
                    isSearchActive: false,
                    isAlertActive: alertActive
                ),
                .cancel
            )
        }
    }

    func testShouldKeepOverlayAfterResignKeyWhilePreviewShowing() {
        XCTAssertTrue(
            OverlayPanelManager.shouldKeepOverlayAfterResignKey(
                isPreviewShowing: true,
                suppressUntil: 0,
                now: 100,
                appIsActive: true
            )
        )
    }

    func testShouldKeepOverlayAfterResignKeyDuringPreviewDismissGrace() {
        XCTAssertTrue(
            OverlayPanelManager.shouldKeepOverlayAfterResignKey(
                isPreviewShowing: false,
                suppressUntil: 100.4,
                now: 100.1,
                appIsActive: true
            )
        )
    }

    func testShouldHideOverlayAfterResignKeyWhenAppInactive() {
        XCTAssertFalse(
            OverlayPanelManager.shouldKeepOverlayAfterResignKey(
                isPreviewShowing: true,
                suppressUntil: 200,
                now: 100,
                appIsActive: false
            )
        )
    }

    func testShouldHideOverlayAfterResignKeyWhenIdle() {
        XCTAssertFalse(
            OverlayPanelManager.shouldKeepOverlayAfterResignKey(
                isPreviewShowing: false,
                suppressUntil: 50,
                now: 100,
                appIsActive: true
            )
        )
    }

    func testPinnedOverlaySurvivesResignEvenWhenAppInactive() {
        XCTAssertTrue(
            OverlayPanelManager.shouldKeepOverlayAfterResignKey(
                isPinned: true,
                isPreviewShowing: false,
                suppressUntil: 0,
                now: 100,
                appIsActive: false
            )
        )
    }

    func testOverlayPanelConsumesSpaceForPreviewWhenSearchInactive() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 49,
                chars: " ",
                isSearchActive: false
            ),
            .consume
        )
    }

    func testOverlayPanelDoesNotConsumeSpaceWhenSearchActive() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 49,
                chars: " ",
                isSearchActive: true,
                keyboardOwner: .searchField
            ),
            .system
        )
    }

    func testOverlayPanelConsumesSpaceWhenSearchCardsOwnFocus() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 49,
                chars: " ",
                isSearchActive: true,
                keyboardOwner: .overlayNavigation
            ),
            .consume
        )
    }

    func testOverlayPanelConsumesCommandCAndCommandPWhenNavigating() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 8,
                isSearchActive: false,
                modifierFlags: .command
            ),
            .consume
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 35,
                isSearchActive: false,
                modifierFlags: .command
            ),
            .consume
        )
    }

    func testOverlayPanelLetsSearchFieldHandleCommandC() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 8,
                isSearchActive: true,
                modifierFlags: .command,
                keyboardOwner: .searchField
            ),
            .system
        )
    }
}
