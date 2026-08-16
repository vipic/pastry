import XCTest
@testable import Pastry

final class SettingsViewTests: XCTestCase {
    func testSettingsTabsIncludeAboutTabForMenuRouting() {
        XCTAssertTrue(SettingsSceneView.SettingsTab.allCases.contains(.about))
        XCTAssertEqual(SettingsSceneView.SettingsTab(rawValue: "about"), .about)
    }

    func testSettingsTabsHaveUniqueAccessibilityIdentifiers() {
        let identifiers = SettingsSceneView.SettingsTab.allCases.map {
            AccessibilityIdentifiers.Settings.sidebarTab($0.rawValue)
        }

        XCTAssertEqual(Set(identifiers).count, SettingsSceneView.SettingsTab.allCases.count)
        XCTAssertEqual(identifiers.first, "settings.tab.general")
        XCTAssertEqual(identifiers.last, "settings.tab.about")
    }
}
