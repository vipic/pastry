import XCTest
@testable import Pastry

final class LocalNaturalLanguageSearchTests: XCTestCase {
    func testRejectsHallucinatedAppThatQueryDidNotMention() {
        XCTAssertNil(
            LocalNaturalLanguageSearchInterpreter.validatedAppName(
                "Brave Browser",
                query: "上个月复制过的大明王朝",
                availableApps: ["Brave Browser", "Safari"]
            )
        )
    }

    func testAcceptsExplicitlyMentionedApp() {
        XCTAssertEqual(
            LocalNaturalLanguageSearchInterpreter.validatedAppName(
                "Brave Browser",
                query: "找 Brave Browser 里复制的内容",
                availableApps: ["Brave Browser", "Safari"]
            ),
            "Brave Browser"
        )
    }

    func testAcceptsControlledAppAlias() {
        XCTAssertEqual(
            LocalNaturalLanguageSearchInterpreter.validatedAppName(
                "WeChat",
                query: "找微信里复制的地址",
                availableApps: ["WeChat"]
            ),
            "WeChat"
        )
    }

    func testRejectsHallucinatedContentKind() {
        XCTAssertEqual(
            LocalNaturalLanguageSearchInterpreter.validatedContentKind(
                "text",
                query: "上个月复制过的大明王朝"
            ),
            .any
        )
    }

    func testAcceptsExplicitContentKind() {
        XCTAssertEqual(
            LocalNaturalLanguageSearchInterpreter.validatedContentKind(
                "link",
                query: "上个月复制的大明王朝链接"
            ),
            .link
        )
    }
}
