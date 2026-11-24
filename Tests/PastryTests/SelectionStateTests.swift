import XCTest
@testable import Pastry

// MARK: - SelectionState 测试套件
// 测试光标导航、Shift 区间选择、鼠标点击交互逻辑

final class SelectionStateTests: XCTestCase {

    // MARK: - 辅助

    /// 创建简单测试用的 ClipboardItem 数组
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

    // MARK: - 全选

    func testSingleItemCountsAsEntireSelectionOnlyAfterExplicitSelectAll() {
        var state = SelectionState()
        let items = makeItems(1)

        state.selectFirst(visibleItems: items)
        XCTAssertFalse(state.isEntireSelection(visibleItems: items))

        state.selectAll(visibleItems: items)
        XCTAssertTrue(state.isEntireSelection(visibleItems: items))

        state.handleTap(item: items[0], cmdDown: false, shiftDown: false, visibleItems: items)
        XCTAssertFalse(state.isEntireSelection(visibleItems: items))
    }

    func testEntireSelectionRequiresAllVisibleItems() {
        var state = SelectionState()
        let items = makeItems(3)
        state.selectedIds = Set(items.prefix(2).map(\.id))
        XCTAssertFalse(state.isEntireSelection(visibleItems: items))

        state.selectedIds.insert(items[2].id)
        XCTAssertTrue(state.isEntireSelection(visibleItems: items))
        XCTAssertFalse(state.isEntireSelection(visibleItems: Array(items.prefix(2))))
    }

    // MARK: - 方向键基础移动

    func testArrowDownFromEmpty() {
        var s = SelectionState()
        let items = makeItems(5)

        s.moveCursor(delta: 1, extend: false, visibleItems: items)

        XCTAssertEqual(s.cursorIndex, 0)
        XCTAssertEqual(s.selectedIds, [items[0].id])
        XCTAssertNil(s.shiftAnchorIdx)
    }

    func testArrowDownThenDown() {
        var s = SelectionState()
        let items = makeItems(5)

        s.moveCursor(delta: 1, extend: false, visibleItems: items)  // → 0
        s.moveCursor(delta: 1, extend: false, visibleItems: items)  // → 1

        XCTAssertEqual(s.cursorIndex, 1)
        XCTAssertEqual(s.selectedIds, [items[1].id])
    }

    func testArrowUpPastTop() {
        var s = SelectionState()
        let items = makeItems(5)

        s.moveCursor(delta: 1, extend: false, visibleItems: items)   // → 0
        s.moveCursor(delta: -1, extend: false, visibleItems: items)  // still 0

        XCTAssertEqual(s.cursorIndex, 0)
    }

    func testArrowDownPastBottom() {
        var s = SelectionState()
        let items = makeItems(3)
        s.cursorIndex = 2
        s.selectedIds = [items[2].id]

        s.moveCursor(delta: 1, extend: false, visibleItems: items)

        XCTAssertEqual(s.cursorIndex, 2)
    }

    // MARK: - Shift 区间选择

    func testShiftArrowExtendsRange() {
        var s = SelectionState()
        let items = makeItems(5)

        // 先普通移动到 0
        s.moveCursor(delta: 1, extend: false, visibleItems: items)
        // Shift+↓ 到 1
        s.moveCursor(delta: 1, extend: true, visibleItems: items)
        // Shift+↓ 到 2
        s.moveCursor(delta: 1, extend: true, visibleItems: items)

        XCTAssertEqual(s.cursorIndex, 2)
        XCTAssertEqual(s.shiftAnchorIdx, 0)
        XCTAssertEqual(s.selectedIds, Set([items[0].id, items[1].id, items[2].id]))
    }

    func testShiftArrowExtendsUpward() {
        var s = SelectionState()
        let items = makeItems(5)
        s.cursorIndex = 3
        s.selectedIds = [items[3].id]

        // Shift+↑ 到 2
        s.moveCursor(delta: -1, extend: true, visibleItems: items)
        // Shift+↑ 到 1
        s.moveCursor(delta: -1, extend: true, visibleItems: items)

        XCTAssertEqual(s.cursorIndex, 1)
        XCTAssertEqual(s.shiftAnchorIdx, 3)
        XCTAssertEqual(s.selectedIds, Set([items[1].id, items[2].id, items[3].id]))
    }

    func testShiftArrowWithNoPriorCursor() {
        var s = SelectionState()
        let items = makeItems(5)

        // 无光标时 Shift+↓ 应退化为普通移动
        s.moveCursor(delta: 1, extend: true, visibleItems: items)

        XCTAssertEqual(s.cursorIndex, 0)
        XCTAssertEqual(s.selectedIds, [items[0].id])
        XCTAssertNil(s.shiftAnchorIdx)
    }

    func testNormalArrowResetsShiftAnchor() {
        var s = SelectionState()
        let items = makeItems(5)

        // 建立区间
        s.moveCursor(delta: 1, extend: false, visibleItems: items)  // → 0
        s.moveCursor(delta: 1, extend: true, visibleItems: items)   // → 0-1
        XCTAssertEqual(s.shiftAnchorIdx, 0)

        // 普通方向键应重置锚点
        s.moveCursor(delta: 1, extend: false, visibleItems: items)  // → 2
        XCTAssertNil(s.shiftAnchorIdx)
        XCTAssertEqual(s.selectedIds, [items[2].id])
    }

    // MARK: - 鼠标点击

    func testNormalClickSelectsSingle() {
        var s = SelectionState()
        let items = makeItems(5)

        s.handleTap(item: items[2], cmdDown: false, shiftDown: false, visibleItems: items)

        XCTAssertEqual(s.cursorIndex, 2)
        XCTAssertEqual(s.selectedIds, [items[2].id])
        XCTAssertEqual(s.lastClickId, items[2].id)
        XCTAssertNil(s.shiftAnchorIdx)
    }

    func testCmdClickToggles() {
        var s = SelectionState()
        let items = makeItems(5)
        s.selectedIds = [items[0].id, items[2].id]

        // 取消选中
        s.handleTap(item: items[2], cmdDown: true, shiftDown: false, visibleItems: items)
        XCTAssertEqual(s.selectedIds, [items[0].id])

        // 加选
        s.handleTap(item: items[3], cmdDown: true, shiftDown: false, visibleItems: items)
        XCTAssertEqual(s.selectedIds, Set([items[0].id, items[3].id]))
    }

    func testShiftClickSelectsRange() {
        var s = SelectionState()
        let items = makeItems(5)

        // 先普通点击 item 1 建立锚点
        s.handleTap(item: items[1], cmdDown: false, shiftDown: false, visibleItems: items)
        // Shift+点击 item 4 扩展区间
        s.handleTap(item: items[4], cmdDown: false, shiftDown: true, visibleItems: items)

        XCTAssertEqual(s.cursorIndex, 4)
        XCTAssertEqual(s.shiftAnchorIdx, 1)
        XCTAssertEqual(s.selectedIds, Set([items[1].id, items[2].id, items[3].id, items[4].id]))
    }

    func testShiftClickPreservesAnchorForSubsequentKeyboard() {
        var s = SelectionState()
        let items = makeItems(8)

        // 点击 2 → Shift+点击 5
        s.handleTap(item: items[2], cmdDown: false, shiftDown: false, visibleItems: items)
        s.handleTap(item: items[5], cmdDown: false, shiftDown: true, visibleItems: items)

        // 键盘 Shift+↓ 应继续从锚点 2 扩展
        s.moveCursor(delta: 1, extend: true, visibleItems: items)

        XCTAssertEqual(s.cursorIndex, 6)
        XCTAssertEqual(s.shiftAnchorIdx, 2)
        XCTAssertEqual(s.selectedIds, Set([
            items[2].id, items[3].id, items[4].id, items[5].id, items[6].id
        ]))
    }

    // MARK: - 键盘→鼠标协同

    func testKeyboardShiftThenMouseShiftContinues() {
        var s = SelectionState()
        let items = makeItems(10)

        // 键盘：点击 1 → Shift+↓ 到 4
        s.handleTap(item: items[1], cmdDown: false, shiftDown: false, visibleItems: items)
        s.moveCursor(delta: 1, extend: true, visibleItems: items)  // 1-2
        s.moveCursor(delta: 1, extend: true, visibleItems: items)  // 1-3
        s.moveCursor(delta: 1, extend: true, visibleItems: items)  // 1-4

        // 鼠标 Shift+点击 8：lastClickId 已被 moveCursor 同步为 items[1].id
        s.handleTap(item: items[8], cmdDown: false, shiftDown: true, visibleItems: items)

        XCTAssertEqual(s.selectedIds, Set((1...8).map { items[$0].id }))
        XCTAssertEqual(s.shiftAnchorIdx, 1)
    }

    // MARK: - 重置

    func testResetClearsAll() {
        var s = SelectionState()
        let items = makeItems(5)
        s.handleTap(item: items[3], cmdDown: false, shiftDown: false, visibleItems: items)

        s.reset()

        XCTAssertTrue(s.selectedIds.isEmpty)
        XCTAssertNil(s.cursorIndex)
        XCTAssertNil(s.shiftAnchorIdx)
        XCTAssertNil(s.lastClickId)
    }

    // MARK: - 默认选中首项（打开面板）

    func testSelectFirstSelectsLeadingCard() {
        var s = SelectionState()
        let items = makeItems(5)

        s.selectFirst(visibleItems: items)

        XCTAssertEqual(s.selectedIds, [items[0].id])
        XCTAssertEqual(s.cursorIndex, 0)
        XCTAssertEqual(s.lastClickId, items[0].id)
        XCTAssertNil(s.shiftAnchorIdx)
    }

    func testSelectFirstOnEmptyListClearsSelection() {
        var s = SelectionState()
        let items = makeItems(3)
        s.handleTap(item: items[1], cmdDown: false, shiftDown: false, visibleItems: items)

        s.selectFirst(visibleItems: [])

        XCTAssertTrue(s.selectedIds.isEmpty)
        XCTAssertNil(s.cursorIndex)
        XCTAssertNil(s.lastClickId)
        XCTAssertNil(s.shiftAnchorIdx)
    }

    func testSelectFirstReplacesPriorMultiSelection() {
        var s = SelectionState()
        let items = makeItems(5)
        s.moveCursor(delta: 1, extend: false, visibleItems: items)
        s.moveCursor(delta: 1, extend: true, visibleItems: items)
        s.moveCursor(delta: 1, extend: true, visibleItems: items)
        XCTAssertGreaterThan(s.selectedIds.count, 1)

        s.selectFirst(visibleItems: items)

        XCTAssertEqual(s.selectedIds, [items[0].id])
        XCTAssertEqual(s.cursorIndex, 0)
        XCTAssertNil(s.shiftAnchorIdx)
    }

    // MARK: - 重置后导航从首位开始

    func testResetThenArrowStartsFromBeginning() {
        var s = SelectionState()
        let items = makeItems(5)

        // 模拟键盘操作：移动到第 2 项
        s.moveCursor(delta: 1, extend: false, visibleItems: items)  // → 0
        s.moveCursor(delta: 1, extend: false, visibleItems: items)  // → 1
        XCTAssertEqual(s.cursorIndex, 1)
        XCTAssertEqual(s.selectedIds, [items[1].id])

        // 模拟删除后 reset（修复前只清 selectedIds，cursorIndex 残留）
        s.reset()

        // 重置后按右箭头 → 应从 0 开始，而非跳到 2
        s.moveCursor(delta: 1, extend: false, visibleItems: items)
        XCTAssertEqual(s.cursorIndex, 0)
        XCTAssertEqual(s.selectedIds, [items[0].id])
    }

    func testResetThenShiftArrowWorksCleanly() {
        var s = SelectionState()
        let items = makeItems(5)

        // 建立区间选择 1-3
        s.moveCursor(delta: 1, extend: false, visibleItems: items)  // → 0
        s.moveCursor(delta: 1, extend: true, visibleItems: items)   // → 0-1
        s.moveCursor(delta: 1, extend: true, visibleItems: items)   // → 0-2
        XCTAssertEqual(s.shiftAnchorIdx, 0)
        XCTAssertEqual(s.selectedIds.count, 3)

        // 模拟删除后 reset
        s.reset()

        // 重置后 Shift+↓ 应退化为普通移动（无光标无历史锚点）
        s.moveCursor(delta: 1, extend: true, visibleItems: items)
        XCTAssertEqual(s.cursorIndex, 0)
        XCTAssertEqual(s.selectedIds, [items[0].id])
        XCTAssertNil(s.shiftAnchorIdx)
    }

    // MARK: - 边界

    func testEmptyItemsDoesNothing() {
        var s = SelectionState()
        s.moveCursor(delta: 1, extend: false, visibleItems: [])
        XCTAssertNil(s.cursorIndex)
        XCTAssertTrue(s.selectedIds.isEmpty)
    }

    func testBoundaryDetectionRequiresExistingCursor() {
        let s = SelectionState()
        let items = makeItems(3)

        XCTAssertFalse(s.wouldHitBoundary(delta: -1, visibleItems: items))
        XCTAssertFalse(s.wouldHitBoundary(delta: 1, visibleItems: items))
    }

    func testBoundaryDetectionAtEdges() {
        let items = makeItems(3)
        var s = SelectionState()

        s.cursorIndex = 0
        XCTAssertTrue(s.wouldHitBoundary(delta: -1, visibleItems: items))
        XCTAssertFalse(s.wouldHitBoundary(delta: 1, visibleItems: items))

        s.cursorIndex = 2
        XCTAssertTrue(s.wouldHitBoundary(delta: 1, visibleItems: items))
        XCTAssertFalse(s.wouldHitBoundary(delta: -1, visibleItems: items))
    }

    func testMoveCursorToIndexSupportsHomeEndStyleNavigation() {
        let items = makeItems(5)
        var s = SelectionState()

        s.moveCursor(to: 4, extend: false, visibleItems: items)
        XCTAssertEqual(s.cursorIndex, 4)
        XCTAssertEqual(s.selectedIds, [items[4].id])

        s.moveCursor(to: 0, extend: false, visibleItems: items)
        XCTAssertEqual(s.cursorIndex, 0)
        XCTAssertEqual(s.selectedIds, [items[0].id])
    }

    func testMoveCursorToIndexCanExtendSelection() {
        let items = makeItems(5)
        var s = SelectionState()
        s.cursorIndex = 1
        s.selectedIds = [items[1].id]

        s.moveCursor(to: 4, extend: true, visibleItems: items)

        XCTAssertEqual(s.cursorIndex, 4)
        XCTAssertEqual(s.shiftAnchorIdx, 1)
        XCTAssertEqual(s.selectedIds, Set([items[1].id, items[2].id, items[3].id, items[4].id]))
    }

    func testBoundaryDetectionForTargetIndex() {
        let items = makeItems(3)
        var s = SelectionState()
        s.cursorIndex = 0

        XCTAssertTrue(s.wouldHitBoundary(targetIndex: 0, visibleItems: items))
        XCTAssertTrue(s.wouldHitBoundary(targetIndex: -10, visibleItems: items))
        XCTAssertFalse(s.wouldHitBoundary(targetIndex: 2, visibleItems: items))
    }

    func testBoundaryDetectionIgnoresEmptyItems() {
        var s = SelectionState()
        s.cursorIndex = 0

        XCTAssertFalse(s.wouldHitBoundary(delta: -1, visibleItems: []))
        XCTAssertFalse(s.wouldHitBoundary(delta: 1, visibleItems: []))
        XCTAssertFalse(s.wouldHitBoundary(targetIndex: 0, visibleItems: []))
    }

    func testShiftClickWithNoAnchorDoesNothing() {
        var s = SelectionState()
        let items = makeItems(5)
        // lastClickId 从未设置，Shift+点击应退化为普通点击
        s.handleTap(item: items[2], cmdDown: false, shiftDown: true, visibleItems: items)

        XCTAssertEqual(s.cursorIndex, 2)
        XCTAssertEqual(s.selectedIds, [items[2].id])
        XCTAssertEqual(s.lastClickId, items[2].id)
    }

    // MARK: - 鼠标多选边角

    func testCmdAndShiftTogetherPrefersShiftRangeWhenAnchorExists() {
        var s = SelectionState()
        let items = makeItems(6)
        s.handleTap(item: items[1], cmdDown: false, shiftDown: false, visibleItems: items)

        // 实现里 shift 分支先于 cmd：⌘⇧ 同时按应按区间处理
        s.handleTap(item: items[4], cmdDown: true, shiftDown: true, visibleItems: items)

        XCTAssertEqual(
            s.selectedIds,
            Set([items[1].id, items[2].id, items[3].id, items[4].id]),
            "⌘+⇧ 同时按下时 shift 区间优先于 cmd toggle"
        )
        XCTAssertEqual(s.shiftAnchorIdx, 1)
    }

    func testPlainClickAfterMultiSelectCollapsesToSingle() {
        var s = SelectionState()
        let items = makeItems(5)
        s.handleTap(item: items[0], cmdDown: false, shiftDown: false, visibleItems: items)
        s.handleTap(item: items[2], cmdDown: true, shiftDown: false, visibleItems: items)
        s.handleTap(item: items[3], cmdDown: true, shiftDown: false, visibleItems: items)
        XCTAssertEqual(s.selectedIds.count, 3)

        s.handleTap(item: items[1], cmdDown: false, shiftDown: false, visibleItems: items)

        XCTAssertEqual(s.selectedIds, [items[1].id])
        XCTAssertNil(s.shiftAnchorIdx)
    }

    func testCmdClickFromEmptySelectionSelectsOnlyThatItem() {
        var s = SelectionState()
        let items = makeItems(4)

        s.handleTap(item: items[2], cmdDown: true, shiftDown: false, visibleItems: items)

        XCTAssertEqual(s.selectedIds, [items[2].id])
        XCTAssertEqual(s.cursorIndex, 2)
        XCTAssertEqual(s.lastClickId, items[2].id)
    }

    func testCmdClickDeselectsUntilEmpty() {
        var s = SelectionState()
        let items = makeItems(3)
        s.handleTap(item: items[0], cmdDown: false, shiftDown: false, visibleItems: items)
        s.handleTap(item: items[1], cmdDown: true, shiftDown: false, visibleItems: items)
        s.handleTap(item: items[0], cmdDown: true, shiftDown: false, visibleItems: items)
        s.handleTap(item: items[1], cmdDown: true, shiftDown: false, visibleItems: items)

        XCTAssertTrue(s.selectedIds.isEmpty)
        XCTAssertEqual(s.lastClickId, items[1].id)
        XCTAssertEqual(s.cursorIndex, 1)
    }

    func testShiftClickBackwardRange() {
        var s = SelectionState()
        let items = makeItems(6)
        s.handleTap(item: items[4], cmdDown: false, shiftDown: false, visibleItems: items)
        s.handleTap(item: items[1], cmdDown: false, shiftDown: true, visibleItems: items)

        XCTAssertEqual(s.cursorIndex, 1)
        XCTAssertEqual(s.shiftAnchorIdx, 4)
        XCTAssertEqual(
            s.selectedIds,
            Set([items[1].id, items[2].id, items[3].id, items[4].id])
        )
    }
}
