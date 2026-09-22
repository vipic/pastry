import XCTest
@testable import Pastry

final class MultiSmartActionTests: XCTestCase {
    private func item(_ format: SourceFormat, index: Int = 0) -> ClipboardItem {
        ClipboardItem(content: "item \(index)", sourceFormat: format)
    }

    func testSelectionModeClassifiesTextImagesAndMixedContent() {
        XCTAssertEqual(
            MultiSmartActionSelection.mode(for: [item(.text), item(.html)]),
            .text
        )
        XCTAssertEqual(
            MultiSmartActionSelection.mode(for: [item(.image), item(.image)]),
            .image
        )
        XCTAssertEqual(
            MultiSmartActionSelection.mode(for: [item(.rtf), item(.image)]),
            .mixed
        )
    }

    func testSelectionModeRejectsSingleItemFilesAndTooManyItems() {
        XCTAssertNil(MultiSmartActionSelection.mode(for: [item(.text)]))
        XCTAssertNil(MultiSmartActionSelection.mode(for: [item(.text), item(.fileURL)]))
        let tooMany = (0 ... MultiSmartActionSelection.maximumItemCount)
            .map { item(.text, index: $0) }
        XCTAssertNil(MultiSmartActionSelection.mode(for: tooMany))
    }

    func testTextSelectionExposesRelationshipAwareActions() {
        XCTAssertEqual(
            MultiSmartActionSelection.actions(for: .text, supportsImageDescription: false),
            [.summarize, .compare, .mergeRewrite, .extractCalendar, .emailDraft, .custom]
        )
    }

    func testImageSelectionOnlyAddsDescriptionWhenAvailable() {
        XCTAssertEqual(
            MultiSmartActionSelection.actions(for: .image, supportsImageDescription: false),
            [.extractAllText, .recognizeBarcodes]
        )
        XCTAssertEqual(
            MultiSmartActionSelection.actions(for: .image, supportsImageDescription: true),
            [.extractAllText, .recognizeBarcodes, .describeImages]
        )
    }

    func testMixedSelectionUsesConservativeActionSet() {
        XCTAssertEqual(
            MultiSmartActionSelection.actions(for: .mixed, supportsImageDescription: true),
            [.summarize, .extractAllText, .custom]
        )
    }
}
