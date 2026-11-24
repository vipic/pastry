import Foundation

// MARK: - 选择状态（纯逻辑，可独立测试）

/// 封装 OverlayView 的选中/光标/区间逻辑，不依赖任何 UI 框架。
struct SelectionState {
    var selectedIds: Set<UUID> = [] {
        didSet { didSelectAll = false }
    }
    private var didSelectAll = false
    var cursorIndex: Int? = nil
    var shiftAnchorIdx: Int? = nil
    var lastClickId: UUID? = nil

    // MARK: - 键盘方向键

    /// 方向键导航。`extend` = Shift 是否按下。
    mutating func moveCursor(delta: Int, extend: Bool, visibleItems: [ClipboardItem]) {
        guard !visibleItems.isEmpty else { return }
        let maxIdx = visibleItems.count - 1
        let currentIdx: Int
        if let ci = cursorIndex {
            currentIdx = ci
        } else {
            currentIdx = delta > 0 ? -1 : visibleItems.count
        }
        let newIdx = max(0, min(maxIdx, currentIdx + delta))
        moveCursor(to: newIdx, currentIdx: currentIdx, extend: extend, visibleItems: visibleItems)
    }

    mutating func moveCursor(to targetIndex: Int, extend: Bool, visibleItems: [ClipboardItem]) {
        guard !visibleItems.isEmpty else { return }
        let maxIdx = visibleItems.count - 1
        let currentIdx = cursorIndex ?? targetIndex
        let newIdx = max(0, min(maxIdx, targetIndex))
        moveCursor(to: newIdx, currentIdx: currentIdx, extend: extend, visibleItems: visibleItems)
    }

    private mutating func moveCursor(
        to newIdx: Int,
        currentIdx: Int,
        extend: Bool,
        visibleItems: [ClipboardItem]
    ) {
        if extend, cursorIndex != nil {
            let anchorIdx = shiftAnchorIdx ?? currentIdx
            shiftAnchorIdx = anchorIdx
            let range = min(anchorIdx, newIdx)...max(anchorIdx, newIdx)
            selectedIds = Set(range.map { visibleItems[$0].id })
        } else {
            selectedIds = [visibleItems[newIdx].id]
            shiftAnchorIdx = nil
        }
        cursorIndex = newIdx
        // 同步 lastClickId
        if let ai = shiftAnchorIdx, ai >= 0, ai < visibleItems.count {
            lastClickId = visibleItems[ai].id
        } else if newIdx < visibleItems.count {
            lastClickId = visibleItems[newIdx].id
        }
    }

    /// 已有光标时，继续向边界外移动会被 clamp。
    func wouldHitBoundary(delta: Int, visibleItems: [ClipboardItem]) -> Bool {
        guard !visibleItems.isEmpty, let cursorIndex else { return false }
        if delta < 0 { return cursorIndex <= 0 }
        if delta > 0 { return cursorIndex >= visibleItems.count - 1 }
        return false
    }

    func wouldHitBoundary(targetIndex: Int, visibleItems: [ClipboardItem]) -> Bool {
        guard !visibleItems.isEmpty, let cursorIndex else { return false }
        let clamped = max(0, min(visibleItems.count - 1, targetIndex))
        return clamped == cursorIndex
    }

    // MARK: - 鼠标点击

    /// 卡片点击。`cmdDown`/`shiftDown` 来自鼠标按下时的修饰键。
    mutating func handleTap(item: ClipboardItem, cmdDown: Bool, shiftDown: Bool, visibleItems: [ClipboardItem]) {
        if shiftDown, let anchorId = lastClickId {
            // Shift+点击：区间选择
            if let anchorIdx = visibleItems.firstIndex(where: { $0.id == anchorId }),
               let clickedIdx = visibleItems.firstIndex(where: { $0.id == item.id }) {
                let range = min(anchorIdx, clickedIdx)...max(anchorIdx, clickedIdx)
                selectedIds = Set(range.map { visibleItems[$0].id })
                cursorIndex = clickedIdx
                shiftAnchorIdx = anchorIdx
            }
        } else if cmdDown {
            // Cmd+点击：toggle
            if selectedIds.contains(item.id) {
                selectedIds.remove(item.id)
            } else {
                selectedIds.insert(item.id)
            }
            lastClickId = item.id
            if let idx = visibleItems.firstIndex(where: { $0.id == item.id }) {
                cursorIndex = idx
            }
        } else {
            // 普通点击：单选
            selectedIds = [item.id]
            lastClickId = item.id
            if let idx = visibleItems.firstIndex(where: { $0.id == item.id }) {
                cursorIndex = idx
                shiftAnchorIdx = nil
            }
        }
    }

    // MARK: - 全选 / 重置 / 默认选中

    mutating func selectAll(visibleItems: [ClipboardItem]) {
        selectedIds = Set(visibleItems.map(\.id))
        didSelectAll = !selectedIds.isEmpty
    }

    /// 单条记录只在显式全选时算作全选；多条记录也允许手动选满。
    func isEntireSelection(visibleItems: [ClipboardItem]) -> Bool {
        (didSelectAll || selectedIds.count > 1)
            && selectedIds.count == visibleItems.count
            && visibleItems.allSatisfy { selectedIds.contains($0.id) }
    }

    mutating func reset() {
        selectedIds = []
        cursorIndex = nil
        shiftAnchorIdx = nil
        lastClickId = nil
    }

    /// 选中列表第一项（打开面板等场景的默认键盘落点）。列表为空时清空选择。
    mutating func selectFirst(visibleItems: [ClipboardItem]) {
        guard let first = visibleItems.first else {
            reset()
            return
        }
        selectedIds = [first.id]
        cursorIndex = 0
        shiftAnchorIdx = nil
        lastClickId = first.id
    }
}
