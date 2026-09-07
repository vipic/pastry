import XCTest
import AppKit
@testable import Pastry

/// 覆盖面板交互策略：鼠标多选管线、空白点击清空约定。
/// 用于防止「⌘/⇧ 多选被 simultaneous 空白手势 reset」这类回归。
final class OverlayInteractionModelTests: XCTestCase {

    private func makeItems(_ count: Int) -> [ClipboardItem] {
        (0..<count).map { i in
            ClipboardItem(
                timestamp: Date(),
                content: "item \(i)",
                sourceFormat: .text,
                appName: nil,
                isPinned: false
            )
        }
    }

    // MARK: - 左键点击模式

    func testCardClickModeDefaultsToEnhanced() {
        XCTAssertEqual(CardClickMode.default, .enhanced)
        XCTAssertEqual(CardClickMode.resolved(stored: nil), .enhanced)
        XCTAssertEqual(CardClickMode.resolved(stored: "bogus"), .enhanced)
        XCTAssertEqual(CardClickMode.resolved(stored: "speed"), .speed)
    }

    func testEnhancedModeClickMatrix() {
        // 未选中 → 选中；已选中再点 → 粘贴（两次单击，非系统双击）
        XCTAssertEqual(
            OverlayInteractionModel.cardClickAction(
                mode: .enhanced, isSelected: false, commandOrShift: false
            ),
            .select
        )
        XCTAssertEqual(
            OverlayInteractionModel.cardClickAction(
                mode: .enhanced, isSelected: true, commandOrShift: false
            ),
            .paste
        )
    }

    func testSpeedModeClickMatrix() {
        // 无论是否已选中，单击都粘贴
        XCTAssertEqual(
            OverlayInteractionModel.cardClickAction(
                mode: .speed, isSelected: false, commandOrShift: false
            ),
            .paste
        )
        XCTAssertEqual(
            OverlayInteractionModel.cardClickAction(
                mode: .speed, isSelected: true, commandOrShift: false
            ),
            .paste
        )
    }

    func testCardClickModifiersAlwaysSelectInBothModes() {
        for mode in CardClickMode.allCases {
            for selected in [false, true] {
                XCTAssertEqual(
                    OverlayInteractionModel.cardClickAction(
                        mode: mode, isSelected: selected, commandOrShift: true
                    ),
                    .select,
                    "⌘/⇧ 在 \(mode) 模式 isSelected=\(selected) 时应多选"
                )
            }
        }
    }

    // MARK: - 修饰键解析

    func testResolveModifiersPrefersEventFlags() {
        let mods = OverlayInteractionModel.resolveCardTapModifiers(
            eventCommand: true,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: true
        )
        XCTAssertTrue(mods.cmdDown)
        XCTAssertTrue(mods.shiftDown, "event 与 monitor 应 OR 合并")
    }

    func testResolveModifiersFallsBackToMonitor() {
        let mods = OverlayInteractionModel.resolveCardTapModifiers(
            eventCommand: false,
            eventShift: false,
            monitoredCommand: true,
            monitoredShift: true
        )
        XCTAssertTrue(mods.cmdDown)
        XCTAssertTrue(mods.shiftDown)
    }

    func testResolveModifiersNeitherPressed() {
        let mods = OverlayInteractionModel.resolveCardTapModifiers(
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false
        )
        XCTAssertFalse(mods.cmdDown)
        XCTAssertFalse(mods.shiftDown)
    }

    func testCardTapModifierFlagsORsEventAndLive() {
        let onlyLive = OverlayInteractionModel.cardTapModifierFlags(
            eventFlags: [],
            liveFlags: .command
        )
        XCTAssertTrue(onlyLive.command)
        XCTAssertFalse(onlyLive.shift)

        let onlyEvent = OverlayInteractionModel.cardTapModifierFlags(
            eventFlags: .shift,
            liveFlags: []
        )
        XCTAssertFalse(onlyEvent.command)
        XCTAssertTrue(onlyEvent.shift)

        let both = OverlayInteractionModel.cardTapModifierFlags(
            eventFlags: .command,
            liveFlags: .shift
        )
        XCTAssertTrue(both.command)
        XCTAssertTrue(both.shift)
    }

    func testNormalizedModifierFlagsStripsDeviceBits() {
        // deviceIndependentFlagsMask 保留高位修饰键；低位是设备相关位，应被剥掉
        var raw: NSEvent.ModifierFlags = [.command, .shift]
        raw.insert(NSEvent.ModifierFlags(rawValue: 0x0000_00FF))
        let normalized = OverlayInteractionModel.normalizedModifierFlags(raw)
        XCTAssertTrue(normalized.contains(.command))
        XCTAssertTrue(normalized.contains(.shift))
        XCTAssertEqual(normalized, raw.intersection(.deviceIndependentFlagsMask))
        XCTAssertNotEqual(normalized.rawValue, raw.rawValue)
    }

    /// 多选中普通点击已选卡片 → 折叠为单选，不粘贴（防 ⌘ 读丢误粘贴）。
    func testEnhancedModeMultiSelectionClickSelectsInsteadOfPaste() {
        XCTAssertEqual(
            OverlayInteractionModel.cardClickAction(
                mode: .enhanced,
                isSelected: true,
                isInMultiSelection: true,
                commandOrShift: false
            ),
            .select,
            "多选中再点已选卡片应折叠选中，不得粘贴"
        )
        // 单选状态下（非多选）保持「再点粘贴」
        XCTAssertEqual(
            OverlayInteractionModel.cardClickAction(
                mode: .enhanced,
                isSelected: true,
                isInMultiSelection: false,
                commandOrShift: false
            ),
            .paste
        )
        // speed 模式不受多选影响：单击即粘贴
        XCTAssertEqual(
            OverlayInteractionModel.cardClickAction(
                mode: .speed,
                isSelected: true,
                isInMultiSelection: true,
                commandOrShift: false
            ),
            .paste
        )
    }

    /// ⌘/⇧ 在多选中也始终优先走 select。
    func testMultiSelectionModifierClickStillSelects() {
        for mode in CardClickMode.allCases {
            let action = OverlayInteractionModel.cardClickAction(
                mode: mode,
                isSelected: true,
                isInMultiSelection: true,
                commandOrShift: true
            )
            XCTAssertEqual(action, .select, "⌘/⇧ 在 \(mode) 模式多选中应走选中")
        }
    }

    /// 回归：多选后 ⌘ 点已选项只移除该项，其余保持选中（Finder 语义）。
    func testCmdClickDeselectOneKeepsOthers() {
        var selection = SelectionState()
        let items = makeItems(4)

        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[0],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[1],
            eventCommand: true,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[2],
            eventCommand: true,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        XCTAssertEqual(selection.selectedIds.count, 3)

        // 模拟拖拽层转发：event 丢 ⌘、仅 monitor / live 管线报 ⌘
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[1],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: true,
            monitoredShift: false,
            visibleItems: items
        )

        XCTAssertEqual(
            selection.selectedIds,
            Set([items[0].id, items[2].id]),
            "⌘ 再点已选项应只移除该项，不得 reset 整批"
        )
    }

    // MARK: - 过滤 / 选中列表 / ⌘ 角标

    func testHasActiveFiltersDetectsEachKind() {
        XCTAssertFalse(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: nil,
                appFilter: nil,
                timeFilter: .any,
                urlFilter: false,
                handoffFilter: false
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "x",
                typeFilter: nil,
                appFilter: nil,
                timeFilter: .any,
                urlFilter: false,
                handoffFilter: false
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: .image,
                appFilter: nil,
                timeFilter: .any,
                urlFilter: false,
                handoffFilter: false
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: nil,
                appFilter: "Safari",
                timeFilter: .any,
                urlFilter: false,
                handoffFilter: false
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: nil,
                appFilter: nil,
                timeFilter: .today,
                urlFilter: false,
                handoffFilter: false
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: nil,
                appFilter: nil,
                timeFilter: .any,
                urlFilter: true,
                handoffFilter: false
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: nil,
                appFilter: nil,
                timeFilter: .any,
                urlFilter: false,
                handoffFilter: true,
                noteFilter: .any
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: nil,
                appFilter: nil,
                timeFilter: .any,
                urlFilter: false,
                handoffFilter: false,
                noteFilter: .withNote
            )
        )
    }

    func testSelectedItemsPreservesVisibleOrder() {
        let items = makeItems(5)
        let selected = OverlayInteractionModel.selectedItems(
            visibleItems: items,
            selectedIds: [items[3].id, items[1].id]
        )
        XCTAssertEqual(selected.map(\.id), [items[1].id, items[3].id])
    }

    func testCursorPreviewItemPrefersCursorIndex() {
        let items = makeItems(4)
        let selected = Set([items[0].id, items[1].id, items[2].id])
        let preview = OverlayInteractionModel.cursorPreviewItem(
            visibleItems: items,
            selectedIds: selected,
            cursorIndex: 2
        )
        XCTAssertEqual(preview?.id, items[2].id)
    }

    func testCursorPreviewItemFallsBackToFirstSelected() {
        let items = makeItems(3)
        let preview = OverlayInteractionModel.cursorPreviewItem(
            visibleItems: items,
            selectedIds: [items[2].id, items[0].id],
            cursorIndex: nil
        )
        XCTAssertEqual(preview?.id, items[0].id)
    }

    func testCopyTargetsPreservesStoreOrder() {
        let items = makeItems(4)
        let targets = OverlayInteractionModel.copyTargets(
            allItems: items,
            selectedIds: [items[3].id, items[1].id]
        )
        XCTAssertEqual(targets.map(\.id), [items[1].id, items[3].id])
    }

    func testSearchCountWidthReserveKeepsStableDigitSlots() {
        // 10→9 时两侧仍按最大位数预留，避免徽标变窄
        XCTAssertEqual(
            OverlayInteractionModel.searchCountWidthReserveText(filteredCount: 10, totalCount: 10),
            "00/00"
        )
        XCTAssertEqual(
            OverlayInteractionModel.searchCountWidthReserveText(filteredCount: 9, totalCount: 10),
            "00/00"
        )
        XCTAssertEqual(
            OverlayInteractionModel.searchCountDisplayText(filteredCount: 9, totalCount: 10),
            "9/10"
        )
        XCTAssertEqual(
            OverlayInteractionModel.searchCountWidthReserveText(filteredCount: 0, totalCount: 0),
            "0/0"
        )
        XCTAssertEqual(
            OverlayInteractionModel.searchCountWidthReserveText(filteredCount: 3, totalCount: 100),
            "000/000"
        )
    }

    func testShouldReselectFirstWhenVisibleIdsChange() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        XCTAssertTrue(
            OverlayInteractionModel.shouldReselectFirstAfterVisibleIdsChange(
                oldIds: [a, b, c],
                newIds: [b, c]
            ),
            "删除后列表 ID 变化应重新选中第一张"
        )
        XCTAssertTrue(
            OverlayInteractionModel.shouldReselectFirstAfterVisibleIdsChange(
                oldIds: [a, b, c],
                newIds: [a, c]
            ),
            "搜索/筛选结果变化应重新选中第一张"
        )
        XCTAssertFalse(
            OverlayInteractionModel.shouldReselectFirstAfterVisibleIdsChange(
                oldIds: [a, b, c],
                newIds: [a, b, c]
            ),
            "ID 序列不变时不应打断当前键盘选择"
        )
        XCTAssertTrue(
            OverlayInteractionModel.shouldReselectFirstAfterVisibleIdsChange(
                oldIds: [],
                newIds: [a]
            )
        )
    }

    func testCommandBadgeIndexOnlyForFirstNineWhileCmdDown() {
        XCTAssertNil(OverlayInteractionModel.commandBadgeIndex(cmdDown: false, itemIndex: 0))
        XCTAssertEqual(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: 0), 1)
        XCTAssertEqual(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: 8), 9)
        XCTAssertNil(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: 9))
        XCTAssertNil(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: -1))
    }

    // MARK: - 横向卡带滚轮策略

    func testNormalizedCardStripDeltaPreservesPrecisePixels() {
        let delta = OverlayInteractionModel.normalizedCardStripDelta(
            hasPreciseDeltas: true,
            scrollingDeltaX: 3.5,
            legacyDeltaX: 3.5,
            pointDeltaX: 2,
            lineDeltaX: 9,
            verticalCandidates: [100]
        )
        XCTAssertEqual(delta, 3.5)
    }

    func testNormalizedCardStripDeltaIgnoresVerticalOnly() {
        let delta = OverlayInteractionModel.normalizedCardStripDelta(
            hasPreciseDeltas: true,
            scrollingDeltaX: 0,
            legacyDeltaX: 0,
            verticalCandidates: [12, -8]
        )
        XCTAssertNil(delta, "仅有竖轴位移时不得映射为卡带滚动")
    }

    func testNormalizedCardStripDeltaScalesTraditionalWheelOnce() {
        let delta = OverlayInteractionModel.normalizedCardStripDelta(
            hasPreciseDeltas: false,
            scrollingDeltaX: -2,
            legacyDeltaX: -1,
            lineDeltaX: -1
        )
        XCTAssertEqual(delta, -28)
    }

    func testNormalizedCardStripDeltaFallsBackToCGLineDelta() {
        let delta = OverlayInteractionModel.normalizedCardStripDelta(
            hasPreciseDeltas: true,
            scrollingDeltaX: 0,
            legacyDeltaX: 0,
            lineDeltaX: 2
        )
        XCTAssertEqual(delta, 28)
    }

    // MARK: - 卡带连续像素滚动

    func testApplyStripPixelScrollFollowsDelta() {
        let result = OverlayInteractionModel.applyStripPixelScroll(
            offsetX: 100,
            delta: -18,
            maxOffsetX: 500
        )
        XCTAssertEqual(result.offsetX, 118, accuracy: 0.01)
        XCTAssertFalse(result.hitLeading)
        XCTAssertFalse(result.hitTrailing)
    }

    func testApplyStripPixelScrollPreservesSmallMovement() {
        let result = OverlayInteractionModel.applyStripPixelScroll(
            offsetX: 100,
            delta: 1.25,
            maxOffsetX: 500
        )
        XCTAssertEqual(result.offsetX, 98.75, accuracy: 0.01)
        XCTAssertFalse(result.hitLeading)
        XCTAssertFalse(result.hitTrailing)
    }

    func testApplyStripPixelScrollClampsAtBothEdges() {
        let leading = OverlayInteractionModel.applyStripPixelScroll(
            offsetX: 2,
            delta: 10,
            maxOffsetX: 500
        )
        XCTAssertEqual(leading.offsetX, 0, accuracy: 0.01)
        XCTAssertTrue(leading.hitLeading)
        XCTAssertFalse(leading.hitTrailing)

        let trailing = OverlayInteractionModel.applyStripPixelScroll(
            offsetX: 495,
            delta: -12,
            maxOffsetX: 500
        )
        XCTAssertEqual(trailing.offsetX, 500, accuracy: 0.01)
        XCTAssertFalse(trailing.hitLeading)
        XCTAssertTrue(trailing.hitTrailing)
    }

    func testKeyboardEdgeGlowDirectionFromDelta() {
        XCTAssertEqual(
            OverlayInteractionModel.stripEdgeTowardHigherIndex(forKeyboardDelta: 1),
            true,
            "向右/向后撞边 → trailing"
        )
        XCTAssertEqual(
            OverlayInteractionModel.stripEdgeTowardHigherIndex(forKeyboardDelta: -1),
            false,
            "向左/向前撞边 → leading"
        )
        XCTAssertNil(OverlayInteractionModel.stripEdgeTowardHigherIndex(forKeyboardDelta: 0))
    }

    func testKeyboardEdgeGlowDirectionFromHomeEnd() {
        XCTAssertEqual(
            OverlayInteractionModel.stripEdgeTowardHigherIndex(forAbsoluteTarget: 0, itemCount: 10),
            false,
            "Home 撞边 → leading"
        )
        XCTAssertEqual(
            OverlayInteractionModel.stripEdgeTowardHigherIndex(forAbsoluteTarget: 9, itemCount: 10),
            true,
            "End 撞边 → trailing"
        )
        XCTAssertNil(
            OverlayInteractionModel.stripEdgeTowardHigherIndex(forAbsoluteTarget: 0, itemCount: 0)
        )
    }

    // MARK: - ⌘/⇧ 点击管线（与 SelectionState 组合）

    func testApplyCardClickCommandToggleMultiSelect() {
        var selection = SelectionState()
        let items = makeItems(5)

        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[0],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[2],
            eventCommand: true,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[4],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: true, // 仅 monitor 报 ⌘
            monitoredShift: false,
            visibleItems: items
        )

        XCTAssertEqual(
            selection.selectedIds,
            Set([items[0].id, items[2].id, items[4].id]),
            "连续 ⌘+点击应累积多选"
        )
    }

    func testApplyCardClickShiftRangeSelect() {
        var selection = SelectionState()
        let items = makeItems(6)

        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[1],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[4],
            eventCommand: false,
            eventShift: true,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )

        XCTAssertEqual(
            selection.selectedIds,
            Set([items[1].id, items[2].id, items[3].id, items[4].id])
        )
        XCTAssertEqual(selection.shiftAnchorIdx, 1)
    }

    func testApplyCardClickShiftUsesMonitorWhenEventFlagsMissing() {
        var selection = SelectionState()
        let items = makeItems(5)

        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[0],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[3],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: true,
            visibleItems: items
        )

        XCTAssertEqual(
            selection.selectedIds,
            Set([items[0].id, items[1].id, items[2].id, items[3].id]),
            "event 未带 ⇧ 时 monitor 应兜底区间选"
        )
    }

    // MARK: - 空白点击清空约定（防 simultaneous 回归）

    func testBackgroundClearOnlyWhenCardDidNotHandleClick() {
        XCTAssertTrue(
            OverlayInteractionModel.shouldClearSelectionOnTrayBackgroundTap(
                cardClickHandledThisEvent: false
            ),
            "点空白应清空"
        )
        XCTAssertFalse(
            OverlayInteractionModel.shouldClearSelectionOnTrayBackgroundTap(
                cardClickHandledThisEvent: true
            ),
            "卡片已处理的同一击不得再清空——simultaneousGesture + reset 会毁掉 ⌘/⇧ 多选"
        )
    }

    /// 回归：模拟「多选成功后同一击再 reset」会清空选择。
    /// UI 层必须用互斥的 onTapGesture（子视图吃掉卡片击），禁止 simultaneous reset。
    func testRegression_resetAfterCmdClickDestroysMultiSelect() {
        var selection = SelectionState()
        let items = makeItems(4)

        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[0],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[2],
            eventCommand: true,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        XCTAssertEqual(selection.selectedIds.count, 2)

        // 错误 UI：simultaneous 空白手势在同一击调用 reset
        if OverlayInteractionModel.shouldClearSelectionOnTrayBackgroundTap(
            cardClickHandledThisEvent: false // 错误地当成空白
        ) {
            selection.reset()
        }
        XCTAssertTrue(
            selection.selectedIds.isEmpty,
            "证明：若把卡片击误判为空白并 reset，多选必丢——UI 不得 simultaneous reset"
        )

        // 正确路径：卡片击已处理 → 不 clear
        selection = SelectionState()
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[0],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[2],
            eventCommand: true,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        if OverlayInteractionModel.shouldClearSelectionOnTrayBackgroundTap(
            cardClickHandledThisEvent: true
        ) {
            selection.reset()
        }
        XCTAssertEqual(selection.selectedIds.count, 2, "正确路径应保留 ⌘ 多选")
    }
}
