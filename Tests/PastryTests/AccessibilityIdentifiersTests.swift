import XCTest
@testable import Pastry

/// 无障碍标识：稳定字符串，供 UI 测试与调试定位。
final class AccessibilityIdentifiersTests: XCTestCase {

    func testOverlayIdentifiersAreStable() {
        XCTAssertEqual(AccessibilityIdentifiers.Overlay.root, "overlay.root")
        XCTAssertEqual(AccessibilityIdentifiers.Overlay.cardContainer, "overlay.card-container")
        XCTAssertEqual(AccessibilityIdentifiers.Overlay.searchField, "overlay.search-field")
        XCTAssertEqual(AccessibilityIdentifiers.Overlay.filterButton, "overlay.filter-button")
        XCTAssertEqual(AccessibilityIdentifiers.Overlay.deleteCancelButton, "overlay.delete-cancel-button")
        XCTAssertEqual(AccessibilityIdentifiers.Overlay.deleteConfirmButton, "overlay.delete-confirm-button")
        XCTAssertEqual(AccessibilityIdentifiers.Overlay.emptyState, "overlay.empty-state")
    }

    func testSettingsIdentifiersAreStable() {
        XCTAssertEqual(AccessibilityIdentifiers.Settings.root, "settings.root")
        XCTAssertEqual(AccessibilityIdentifiers.Settings.clearAllButton, "settings.clear-all-button")
        XCTAssertEqual(AccessibilityIdentifiers.Settings.excludedAddButton, "settings.excluded-add-button")
    }

    func testCardIdentifierEmbedsId() {
        let id = "abc-123"
        XCTAssertEqual(AccessibilityIdentifiers.Overlay.card(id), "overlay.card.abc-123")
    }

    func testOnboardingIdentifiersAreStable() {
        XCTAssertEqual(AccessibilityIdentifiers.Onboarding.root, "onboarding.root")
        XCTAssertEqual(AccessibilityIdentifiers.Onboarding.primaryButton, "onboarding.primary-button")
        XCTAssertEqual(AccessibilityIdentifiers.Onboarding.permissionButton, "onboarding.permission-button")
        XCTAssertEqual(AccessibilityIdentifiers.Onboarding.copySampleButton, "onboarding.copy-sample-button")
        XCTAssertEqual(AccessibilityIdentifiers.Onboarding.skipStepButton, "onboarding.skip-step-button")
    }

    func testAllStaticIdentifiersAreUnique() {
        let ids = [
            AccessibilityIdentifiers.Overlay.root,
            AccessibilityIdentifiers.Overlay.cardContainer,
            AccessibilityIdentifiers.Overlay.searchButton,
            AccessibilityIdentifiers.Overlay.searchField,
            AccessibilityIdentifiers.Overlay.clearSearchButton,
            AccessibilityIdentifiers.Overlay.filterButton,
            AccessibilityIdentifiers.Overlay.allTab,
            AccessibilityIdentifiers.Overlay.pinnedTab,
            AccessibilityIdentifiers.Overlay.settingsButton,
            AccessibilityIdentifiers.Overlay.deleteCancelButton,
            AccessibilityIdentifiers.Overlay.deleteConfirmButton,
            AccessibilityIdentifiers.Overlay.emptyState,
            AccessibilityIdentifiers.Settings.root,
            AccessibilityIdentifiers.Settings.sidebar,
            AccessibilityIdentifiers.Settings.languagePicker,
            AccessibilityIdentifiers.Settings.launchAtLoginToggle,
            AccessibilityIdentifiers.Settings.soundToggle,
            AccessibilityIdentifiers.Settings.linkPreviewNetworkToggle,
            AccessibilityIdentifiers.Settings.performanceLoggingToggle,
            AccessibilityIdentifiers.Settings.clearAllButton,
            AccessibilityIdentifiers.Settings.accessibilityRow,
            AccessibilityIdentifiers.Settings.accessibilityGrantButton,
            AccessibilityIdentifiers.Settings.excludedAddButton,
            AccessibilityIdentifiers.Onboarding.root,
            AccessibilityIdentifiers.Onboarding.laterButton,
            AccessibilityIdentifiers.Onboarding.backButton,
            AccessibilityIdentifiers.Onboarding.primaryButton,
            AccessibilityIdentifiers.Onboarding.permissionButton,
            AccessibilityIdentifiers.Onboarding.copySampleButton,
            AccessibilityIdentifiers.Onboarding.skipStepButton,
        ]
        XCTAssertEqual(Set(ids).count, ids.count, "a11y id 不得重复")
        for id in ids {
            XCTAssertFalse(id.isEmpty)
            XCTAssertFalse(id.contains(" "), "id 不宜含空格: \(id)")
        }
    }
}
