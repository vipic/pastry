enum AccessibilityIdentifiers {
    enum Overlay {
        static let root = "overlay.root"
        static let cardContainer = "overlay.card-container"
        static let searchButton = "overlay.search-button"
        static let searchField = "overlay.search-field"
        static let clearSearchButton = "overlay.clear-search-button"
        static let filterButton = "overlay.filter-button"
        static let allTab = "overlay.tab.all"
        static let pinnedTab = "overlay.tab.pinned"
        static let settingsButton = "overlay.settings-button"
        static let multiPasteButton = "overlay.multi-paste-button"
        static let multiCopyButton = "overlay.multi-copy-button"
        static let multiDeleteButton = "overlay.multi-delete-button"
        static let deleteCancelButton = "overlay.delete-cancel-button"
        static let deleteConfirmButton = "overlay.delete-confirm-button"
        static let emptyState = "overlay.empty-state"
        static let emptyCopyHint = "overlay.empty-copy-hint"
        static let accessibilityBanner = "overlay.accessibility-banner"
        static func card(_ id: String) -> String { "overlay.card.\(id)" }
    }

    enum Settings {
        static let root = "settings.root"
        static let sidebar = "settings.sidebar"
        static let languagePicker = "settings.language-picker"
        static let maxItemsPicker = "settings.max-items-picker"
        static let maxAgePicker = "settings.max-age-picker"
        static let launchAtLoginToggle = "settings.launch-at-login-toggle"
        static let soundToggle = "settings.sound-toggle"
        static let cardClickModeToggle = "settings.card-click-mode-toggle"
        static let deleteRequiresConfirmationToggle = "settings.delete-requires-confirmation-toggle"
        static let linkPreviewNetworkToggle = "settings.link-preview-network-toggle"
        static let performanceLoggingToggle = "settings.performance-logging-toggle"
        static let clearAllButton = "settings.clear-all-button"
        static let accessibilityRow = "settings.accessibility-row"
        static let accessibilityGrantButton = "settings.accessibility-grant-button"
        static let excludedAddButton = "settings.excluded-add-button"
        static func sidebarTab(_ rawValue: String) -> String { "settings.tab.\(rawValue)" }
    }

    enum Onboarding {
        static let root = "onboarding.root"
        static let laterButton = "onboarding.later-button"
        static let backButton = "onboarding.back-button"
        static let primaryButton = "onboarding.primary-button"
        static let permissionButton = "onboarding.permission-button"
        static let copySampleButton = "onboarding.copy-sample-button"
        static let skipStepButton = "onboarding.skip-step-button"
    }
}
