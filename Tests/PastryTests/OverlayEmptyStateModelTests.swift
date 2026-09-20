import XCTest
@testable import Pastry

final class OverlayEmptyStateModelTests: XCTestCase {
    func testNoHistoryState() {
        let model = OverlayEmptyStateModel.resolve(isPinnedTab: false, hasActiveFilters: false)
        XCTAssertEqual(model.icon, "clipboard")
        XCTAssertEqual(model.title, L10n["empty.no_history"])
        XCTAssertEqual(model.subtitle, L10n["empty.no_history_hint"])
        XCTAssertTrue(model.showsCopyTryHint, "空历史应展示复制示意")
    }

    func testNoPinsState() {
        let model = OverlayEmptyStateModel.resolve(isPinnedTab: true, hasActiveFilters: false)
        XCTAssertEqual(model.title, L10n["empty.no_pins"])
        XCTAssertEqual(model.subtitle, L10n["empty.no_pins_hint"])
        XCTAssertFalse(model.showsCopyTryHint)
    }

    func testNoResultsStateTakesPriorityOverPinnedTab() {
        let model = OverlayEmptyStateModel.resolve(isPinnedTab: true, hasActiveFilters: true)
        XCTAssertEqual(model.icon, "magnifyingglass")
        XCTAssertEqual(model.title, L10n["empty.no_results"])
        XCTAssertEqual(model.subtitle, L10n["empty.no_results_hint"])
        XCTAssertFalse(model.showsCopyTryHint)
    }
}
