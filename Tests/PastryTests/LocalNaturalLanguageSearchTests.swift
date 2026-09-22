import XCTest
@testable import Pastry

final class LocalNaturalLanguageSearchTests: XCTestCase {
    func testParsesLastWeekAsPreviousMondayThroughSunday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!

        let range = try XCTUnwrap(NaturalLanguageDateParser.range(in: "上周关于吃饭的内容", now: now, calendar: calendar))

        XCTAssertEqual(calendar.component(.weekday, from: range.lowerBound), 2)
        XCTAssertEqual(calendar.component(.day, from: range.lowerBound), 14)
        XCTAssertEqual(calendar.component(.day, from: range.upperBound), 21)
        XCTAssertEqual(calendar.component(.hour, from: range.lowerBound), 0)
    }

    func testParsesRelativeDaysAtCalendarDayBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 18))!

        let range = try XCTUnwrap(NaturalLanguageDateParser.range(in: "大前天复制的", now: now, calendar: calendar))

        XCTAssertEqual(calendar.component(.day, from: range.lowerBound), 20)
        XCTAssertEqual(calendar.component(.day, from: range.upperBound), 21)
    }

    func testIntentAppliesHardDateAndExplicitTypeConstraints() throws {
        let start = Date(timeIntervalSince1970: 100)
        let end = Date(timeIntervalSince1970: 200)
        let intent = NaturalLanguageSearchIntent(
            keywords: [],
            semanticQuery: "吃饭",
            appName: nil,
            contentKind: .text,
            startDate: start,
            endDate: end,
            favoritesOnly: false,
            handoffOnly: false,
            noteRequirement: .any
        )

        let insideRange = ClipboardItem(
            timestamp: Date(timeIntervalSince1970: 150),
            content: "午饭安排",
            sourceFormat: .text
        )
        let outsideRange = ClipboardItem(
            timestamp: end,
            content: "午饭安排",
            sourceFormat: .text
        )
        let wrongType = ClipboardItem(
            timestamp: Date(timeIntervalSince1970: 150),
            content: "午饭安排",
            sourceFormat: .image
        )

        XCTAssertTrue(intent.matches(insideRange))
        XCTAssertFalse(intent.matches(outsideRange))
        XCTAssertFalse(intent.matches(wrongType))
    }

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

final class SemanticSearchFusionTests: XCTestCase {
    func testReciprocalRankFusionCombinesIndependentRankingsAndDeduplicates() {
        let lexical = UUID()
        let semantic = UUID()
        let shared = UUID()

        let result = SemanticSearchFusion.rankedIDs(
            [[lexical, shared], [semantic, shared]],
            limit: 3
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.first, shared)
        XCTAssertEqual(Set(result), [lexical, semantic, shared])
    }
}
