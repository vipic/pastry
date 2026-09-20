struct OverlayEmptyStateModel: Equatable {
    let icon: String
    let title: String
    let subtitle: String
    /// 空历史时展示「复制任意内容试试」示意芯片
    let showsCopyTryHint: Bool

    static func resolve(isPinnedTab: Bool, hasActiveFilters: Bool) -> OverlayEmptyStateModel {
        if isPinnedTab && !hasActiveFilters {
            return OverlayEmptyStateModel(
                icon: "bookmark.slash",
                title: L10n["empty.no_pins"],
                subtitle: L10n["empty.no_pins_hint"],
                showsCopyTryHint: false
            )
        }
        if hasActiveFilters {
            return OverlayEmptyStateModel(
                icon: "magnifyingglass",
                title: L10n["empty.no_results"],
                subtitle: L10n["empty.no_results_hint"],
                showsCopyTryHint: false
            )
        }
        return OverlayEmptyStateModel(
            icon: "clipboard",
            title: L10n["empty.no_history"],
            subtitle: L10n["empty.no_history_hint"],
            showsCopyTryHint: true
        )
    }
}
