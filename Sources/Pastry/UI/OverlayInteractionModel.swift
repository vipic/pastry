import AppKit
import Foundation

// MARK: - 卡片左键点击模式

/// 卡片主键点击策略（设置「左键点击」）。
enum CardClickMode: String, CaseIterable, Identifiable {
    /// A 当前增强：单击选中；再点已选中卡片 → 粘贴（两次单击，非系统双击）
    case enhanced
    /// B 极速：单击即粘贴
    case speed

    var id: String { rawValue }

    static let `default` = CardClickMode.enhanced

    static func resolved(stored: String?) -> CardClickMode {
        guard let stored, let mode = CardClickMode(rawValue: stored) else {
            return .default
        }
        return mode
    }

}

/// 单击主键后的动作。
enum CardClickAction: Equatable {
    case select
    case paste
}

enum OverlayInteractionModel {
    /// 根据点击模式解析卡片左键行为。⌘/⇧ 始终走选中（多选）。
    ///
    /// - enhanced：未选中 → 选中；**单选状态下再点** → 粘贴（看起来像双击，实为两次单击）
    /// - enhanced + 多选：普通点击已选卡片 → 折叠为单选（Finder 语义），**不粘贴**；
    ///   批量粘贴走 Enter / 工具栏。这样 ⌘ 偶发读丢时最多折叠选择，不会误触发粘贴。
    /// - speed：单击 → 粘贴
    /// - Enter 粘贴由键盘路由处理，两种模式一致
    static func cardClickAction(
        mode: CardClickMode,
        isSelected: Bool,
        isInMultiSelection: Bool = false,
        commandOrShift: Bool
    ) -> CardClickAction {
        if commandOrShift { return .select }
        switch mode {
        case .enhanced:
            if isInMultiSelection { return .select }
            return isSelected ? .paste : .select
        case .speed:
            return .paste
        }
    }

    static func hasActiveFilters(
        searchQuery: String,
        typeFilter: SourceFormat?,
        appFilter: String?,
        timeFilter: StoreManager.TimeFilter,
        urlFilter: Bool,
        handoffFilter: Bool,
        noteFilter: StoreManager.NoteFilter = .any
    ) -> Bool {
        !searchQuery.isEmpty
            || typeFilter != nil
            || appFilter != nil
            || timeFilter != .any
            || urlFilter
            || handoffFilter
            || noteFilter != .any
    }

    static func selectedItems(
        visibleItems: [ClipboardItem],
        selectedIds: Set<UUID>
    ) -> [ClipboardItem] {
        visibleItems.filter { selectedIds.contains($0.id) }
    }

    /// Space 预览目标：光标项；无光标时回退到可见选中的第一项。
    static func cursorPreviewItem(
        visibleItems: [ClipboardItem],
        selectedIds: Set<UUID>,
        cursorIndex: Int?
    ) -> ClipboardItem? {
        if let cursorIndex, cursorIndex >= 0, cursorIndex < visibleItems.count {
            return visibleItems[cursorIndex]
        }
        return selectedItems(visibleItems: visibleItems, selectedIds: selectedIds).first
    }

    /// ⌘C / 工具栏复制的目标列表（保持可见顺序）。
    static func copyTargets(
        allItems: [ClipboardItem],
        selectedIds: Set<UUID>
    ) -> [ClipboardItem] {
        guard !selectedIds.isEmpty else { return [] }
        return allItems.filter { selectedIds.contains($0.id) }
    }

    /// 可见列表 ID 序列变化时（删除 / 搜索 / 筛选 / 新条目），应重新默认选中第一张。
    static func shouldReselectFirstAfterVisibleIdsChange(
        oldIds: [UUID],
        newIds: [UUID]
    ) -> Bool {
        oldIds != newIds
    }

    /// 搜索计数徽标的等宽占位串，避免 `10→9` 时宽度收缩导致布局抖动。
    /// 两侧位数取 filtered / total 的较大值（至少 1）。
    static func searchCountWidthReserveText(filteredCount: Int, totalCount: Int) -> String {
        let digits = max(
            String(max(0, filteredCount)).count,
            String(max(0, totalCount)).count,
            1
        )
        let zeros = String(repeating: "0", count: digits)
        return "\(zeros)/\(zeros)"
    }

    static func searchCountDisplayText(filteredCount: Int, totalCount: Int) -> String {
        "\(max(0, filteredCount))/\(max(0, totalCount))"
    }

    static func commandBadgeIndex(cmdDown: Bool, itemIndex: Int) -> Int? {
        guard cmdDown, itemIndex >= 0, itemIndex < 9 else { return nil }
        return itemIndex + 1
    }

    // MARK: - 鼠标多选（可单测的点击管线）

    /// 规范化修饰键（去掉设备相关位），避免 `.contains(.command)` 偶发失效。
    static func normalizedModifierFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(.deviceIndependentFlagsMask)
    }

    /// 卡片点击时读取修饰键：事件 flags ∪ 实时 flags。
    /// SwiftUI `onTapGesture` 触发时 `currentEvent` 经常丢 ⌘/⇧，必须合并 live。
    ///
    /// 注意：不要给 `liveFlags` 写默认值 `= NSEvent.modifierFlags`——与类型同名，
    /// Swift 会把类型位解析成属性访问而编译失败。调用方传入 `NSEvent.modifierFlags`。
    static func cardTapModifierFlags(
        eventFlags: NSEvent.ModifierFlags,
        liveFlags: NSEvent.ModifierFlags
    ) -> (command: Bool, shift: Bool) {
        let event = normalizedModifierFlags(eventFlags)
        let live = normalizedModifierFlags(liveFlags)
        return (
            event.contains(.command) || live.contains(.command),
            event.contains(.shift) || live.contains(.shift)
        )
    }

    /// 便捷读取：`currentEvent` ∪ 实时修饰键。
    static func readCardTapModifierFlags(currentEvent: NSEvent? = NSApp.currentEvent) -> (command: Bool, shift: Bool) {
        cardTapModifierFlags(
            eventFlags: currentEvent?.modifierFlags ?? [],
            liveFlags: NSEvent.modifierFlags
        )
    }

    /// 合并「事件/live 读取」与「mouseDown monitor」两路修饰键。
    static func resolveCardTapModifiers(
        eventCommand: Bool,
        eventShift: Bool,
        monitoredCommand: Bool,
        monitoredShift: Bool
    ) -> (cmdDown: Bool, shiftDown: Bool) {
        (
            eventCommand || monitoredCommand,
            eventShift || monitoredShift
        )
    }

    /// 卡片单击完整管线：解析修饰键 → SelectionState.handleTap。
    /// OverlayView 与单测共用，避免 UI 层手误绕过逻辑。
    static func applyCardClick(
        selection: inout SelectionState,
        item: ClipboardItem,
        eventCommand: Bool,
        eventShift: Bool,
        monitoredCommand: Bool,
        monitoredShift: Bool,
        visibleItems: [ClipboardItem]
    ) {
        let mods = resolveCardTapModifiers(
            eventCommand: eventCommand,
            eventShift: eventShift,
            monitoredCommand: monitoredCommand,
            monitoredShift: monitoredShift
        )
        selection.handleTap(
            item: item,
            cmdDown: mods.cmdDown,
            shiftDown: mods.shiftDown,
            visibleItems: visibleItems
        )
    }

    /// 托盘空白点击是否应清空选择。
    ///
    /// 产品约定：空白 `onTapGesture` 清空；**绝不能**与卡片点击用
    /// `simultaneousGesture` 绑在一起——否则 ⌘/⇧ 多选会在同一击被 reset。
    /// 子视图吃掉卡片手势时，父级 `onTapGesture` 不会触发（这是正确路径）。
    static func shouldClearSelectionOnTrayBackgroundTap(
        cardClickHandledThisEvent: Bool
    ) -> Bool {
        !cardClickHandledThisEvent
    }

    // MARK: - 横向卡带滚轮

    /// 从候选轴位移中选出卡带可用 delta。
    /// **只使用水平轴**；竖滚轮不得映射为横向（避免方向迷惑）。
    static func preferredCardStripDelta(
        horizontalCandidates: [CGFloat],
        verticalCandidates: [CGFloat] = []
    ) -> CGFloat? {
        _ = verticalCandidates // 显式忽略，防止以后误用
        let bestX = horizontalCandidates.max(by: { abs($0) < abs($1) }) ?? 0
        return abs(bestX) > 0.01 ? bestX : nil
    }

    /// 累计滚轮位移并换算成卡片步进数。
    /// AppKit 符号：负 delta 向索引更大的方向滚动，正 delta 向前滚动。
    static func consumeStripScrollSteps(
        accumulator: inout CGFloat,
        delta: CGFloat,
        threshold: CGFloat = 4
    ) -> Int {
        guard threshold > 0 else { return 0 }
        accumulator += delta
        var steps = 0
        while accumulator <= -threshold {
            accumulator += threshold
            steps += 1
        }
        while accumulator >= threshold {
            accumulator -= threshold
            steps -= 1
        }
        return steps
    }

    /// 根据卡片带自身的当前位置计算下一个 SwiftUI 滚动目标。
    /// 位置与选中光标分离，避免选中卡片后侧滚被反复拉回同一位置。
    static func advanceStripScrollIndex(
        current: Int,
        steps: Int,
        itemCount: Int
    ) -> (index: Int, hitEdge: Bool) {
        guard itemCount > 0 else { return (0, false) }
        let base = min(max(0, current), itemCount - 1)
        let proposed = base + steps
        let index = min(max(0, proposed), itemCount - 1)
        return (index, proposed != index)
    }

    /// 键盘已在边界再按同向时，光晕朝向是否为「索引增大侧」（trailing）。
    /// `delta > 0` → trailing；`delta < 0` → leading；`0` → 无方向。
    static func stripEdgeTowardHigherIndex(forKeyboardDelta delta: Int) -> Bool? {
        if delta > 0 { return true }
        if delta < 0 { return false }
        return nil
    }

    /// Home / End 等绝对跳转撞边时：目标落在末位 → trailing，否则 leading。
    static func stripEdgeTowardHigherIndex(forAbsoluteTarget targetIndex: Int, itemCount: Int) -> Bool? {
        guard itemCount > 0 else { return nil }
        return targetIndex >= itemCount - 1
    }
}
