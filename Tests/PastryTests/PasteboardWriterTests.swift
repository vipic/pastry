import Cocoa
import XCTest
@testable import Pastry

final class PasteboardWriterTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.clearContents()
        pasteboard = nil
    }

    func testTextUsesFullContentProvider() async {
        let item = ClipboardItem(content: "truncated", sourceFormat: .text)

        let result = await PasteboardWriter.write(
            item,
            to: pasteboard,
            options: .storeSingle,
            loadFullContent: { _ in "full text content" }
        )

        XCTAssertEqual(result, .written)
        XCTAssertEqual(pasteboard.string(forType: .string), "full text content")
    }

    func testRichTextWritesStringAndOriginalFormat() async {
        let raw = Data("{\\rtf1\\ansi Hello}".utf8)
        let item = ClipboardItem(
            content: "Hello",
            sourceFormat: .rtf,
            rawFormatData: raw,
            rawFormatType: NSPasteboard.PasteboardType.rtf.rawValue
        )

        let result = await PasteboardWriter.write(item, to: pasteboard, options: .storeSingle)

        XCTAssertEqual(result, .written)
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello")
        XCTAssertEqual(pasteboard.data(forType: .rtf), raw)
    }

    func testOverlaySingleFiltersMissingFileURLs() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let existing = dir.appendingPathComponent("existing.txt")
        let missing = dir.appendingPathComponent("missing.txt")
        try "ok".write(to: existing, atomically: true, encoding: .utf8)
        let item = ClipboardItem(
            content: "\(existing.path)\n\(missing.path)",
            sourceFormat: .fileURL
        )

        let result = await PasteboardWriter.write(item, to: pasteboard, options: .overlaySingle)
        let objects = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]

        XCTAssertEqual(result, .written)
        XCTAssertEqual(objects, [existing])
    }

    func testOverlaySingleRejectsAllMissingFileURLs() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.txt")
        let item = ClipboardItem(content: missing.path, sourceFormat: .fileURL)
        pasteboard.setString("用户在别处复制的内容", forType: .string)

        let result = await PasteboardWriter.write(item, to: pasteboard, options: .overlaySingle)

        XCTAssertEqual(result, .noWritableContent)
        // 判定为不可写时不得清空剪贴板：否则用户同时失去原内容和本次操作
        XCTAssertEqual(pasteboard.string(forType: .string), "用户在别处复制的内容")
    }

    func testUnreadableImageKeepsExistingClipboard() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.png")
        let item = ClipboardItem(content: missing.path, sourceFormat: .image)
        pasteboard.setString("用户在别处复制的内容", forType: .string)

        let result = await PasteboardWriter.write(item, to: pasteboard, options: .overlaySingle)

        XCTAssertEqual(result, .noWritableContent)
        XCTAssertEqual(pasteboard.string(forType: .string), "用户在别处复制的内容")
    }

    func testClearSystemClipboardLeavesEmptyStringType() {
        pasteboard.setString("old", forType: .string)

        PasteboardWriter.clearSystemClipboard(to: pasteboard)

        XCTAssertTrue(pasteboard.types?.contains(.string) == true)
        XCTAssertEqual(pasteboard.string(forType: .string), "")
    }

    func testHTMLWritesStringAndRawHTML() async {
        let raw = Data("<p>Hi</p>".utf8)
        let item = ClipboardItem(
            content: "Hi",
            sourceFormat: .html,
            rawFormatData: raw,
            rawFormatType: NSPasteboard.PasteboardType.html.rawValue
        )

        let result = await PasteboardWriter.write(item, to: pasteboard, options: .storeSingle)

        XCTAssertEqual(result, .written)
        XCTAssertEqual(pasteboard.string(forType: .string), "Hi")
        XCTAssertEqual(pasteboard.data(forType: .html), raw)
    }

    func testStoreSingleKeepsMissingFileURLEntriesAsObjects() async {
        // storeSingle 不过滤缺失路径（与 overlaySingle 不同）
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("gone.txt")
        let item = ClipboardItem(content: missing.path, sourceFormat: .fileURL)

        let result = await PasteboardWriter.write(item, to: pasteboard, options: .storeSingle)

        XCTAssertEqual(result, .written)
        let objects = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        XCTAssertEqual(objects?.map(\.path), [missing.path])
    }
}
