import XCTest
import SwiftUI
@testable import Pastry

// MARK: - 文件预览测试套件
// 验证真实采集、文件路径与链接处理、预览策略和拖拽载荷
// 所有剪贴板操作使用独立 pasteboard，不触及系统剪贴板

final class FilePreviewTests: XCTestCase {

    // MARK: - FilePreviewStyle 策略映射

    func testImageExtensionsMapToThumbnail() {
        let imageTypes = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "heif"]
        for ext in imageTypes {
            let style = ClipboardCardView.filePreviewStyle(for: URL(fileURLWithPath: "/tmp/test.\(ext)"))
            XCTAssertEqual(style, .thumbnail, "\(ext) 应映射为 .thumbnail")
        }
    }

    func testNonImageExtensionsMapToSystemIcon() {
        let nonImageTypes = ["pdf", "svg", "dmg", "zip", "mp4", "docx", "xlsx", ""]
        for ext in nonImageTypes {
            let style = ClipboardCardView.filePreviewStyle(for: URL(fileURLWithPath: "/tmp/test.\(ext)"))
            XCTAssertEqual(style, .systemIcon, "\(ext.isEmpty ? "(无扩展名)" : ext) 应映射为 .systemIcon")
        }
    }

    func testExtensionCaseInsensitive() {
        let cases = ["PNG", "JPG", "GIF", "Pdf", "SVG"]
        let expected: [ClipboardCardView.FilePreviewStyle] = [.thumbnail, .thumbnail, .thumbnail, .systemIcon, .systemIcon]
        for (i, ext) in cases.enumerated() {
            XCTAssertEqual(
                ClipboardCardView.filePreviewStyle(for: URL(fileURLWithPath: "/tmp/test.\(ext)")),
                expected[i],
                "\(ext) 大小写不敏感"
            )
        }
    }

    // MARK: - 链接标题归一化

    func testLinkTitleRemovesDuplicatedHostSuffix() {
        let preview = LinkPreviewLoader.Preview(
            title: "Pastry Release - example.com",
            description: nil,
            imageURL: nil,
            host: "example.com"
        )
        let text = ClipboardCardView.linkCardText(url: URL(string: "https://example.com/releases")!, preview: preview)

        XCTAssertEqual(text.title, "Pastry Release")
    }

    // MARK: - ClipboardMonitor 读取优先级：fileURL 优于 image
    // 使用独立 pasteboard，不污染系统剪贴板

    /// 创建测试用独立 pasteboard
    private func makeTestPasteboard(_ name: String) -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("test.hermes.pastry.\(name)"))
    }

    func testImageFileClassifiedAsImage() {
        let pb = makeTestPasteboard("fileURL")

        let testDir = NSTemporaryDirectory()
        let imgPath = (testDir as NSString).appendingPathComponent("test_file.png")
        let testURL = URL(fileURLWithPath: imgPath)
        pb.writeObjects([testURL as NSURL])

        let item = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNotNil(item, "有图片文件 URL 时应返回 item")
        XCTAssertEqual(item?.sourceFormat, .image)
    }

    func testImageReadsWhenNoFileURL() {
        let pb = makeTestPasteboard("imageOnly")

        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        guard let tiffData = image.tiffRepresentation else {
            XCTFail("无法生成 TIFF 数据")
            return
        }
        pb.setData(tiffData, forType: .tiff)

        XCTAssertNil(ClipboardMonitor.readFileURLsForTesting(from: pb),
                     "仅图片数据时 fileURL 应为 nil")

        let img = ClipboardMonitor.readImageDataForTesting(from: pb)
        XCTAssertNotNil(img, "TIFF 数据应可读为图片")
    }

    func testImageOpenableURLPrefersOriginalCacheFile() {
        let pngData = generateTestPNGData(width: 16, height: 16)
        let image = NSImage(data: pngData)!
        let thumbPath = ImageCacheManager.shared.save(image: image, data: pngData)!
        let originalPath = ImageCacheManager.shared.originalPath(forThumbnail: thumbPath)!
        let item = ClipboardItem(content: thumbPath, sourceFormat: .image)

        let openableURL = card(for: item).openableURL

        XCTAssertEqual(openableURL?.path, originalPath)
        XCTAssertTrue(originalPath.hasSuffix(".original.png"))
    }

    func testImageDragProviderUsesReadablePNGName() {
        let pngData = generateTestPNGData(width: 16, height: 16)
        let image = NSImage(data: pngData)!
        let thumbPath = ImageCacheManager.shared.save(image: image, data: pngData)!
        let item = ClipboardItem(content: thumbPath, sourceFormat: .image)

        let provider = DragPayloadBuilder.provider(for: item)

        XCTAssertEqual(provider.suggestedName, "Pastry Image.png")
    }

    func testBothFileURLAndImageOnPasteboard() {
        let pb = makeTestPasteboard("both")

        let testDir = NSTemporaryDirectory()
        let imgPath = (testDir as NSString).appendingPathComponent("photo.jpg")
        let testURL = URL(fileURLWithPath: imgPath)

        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        guard let tiffData = image.tiffRepresentation else {
            XCTFail("无法生成 TIFF 数据")
            return
        }

        pb.declareTypes([.fileURL, .tiff], owner: nil)
        pb.writeObjects([testURL as NSURL])
        pb.setData(tiffData, forType: .tiff)

        let fileItem = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNotNil(fileItem, "fileURL reader 应能读取")
        let imgItem = ClipboardMonitor.readImageDataForTesting(from: pb)
        XCTAssertNotNil(imgItem, "image reader 应能读取")
    }

    private func generateTestPNGData(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return bitmap.representation(using: .png, properties: [:])!
    }

    // MARK: - 文本类型判断（isTextType）

    func testTextTypesReturnTrue() {
        let textTypes: [SourceFormat] = [.text, .rtf, .html]
        for ct in textTypes {
            XCTAssertTrue(card(for: makeItem("", ct)).isTextType,
                          "\(ct) 应为文本类")
        }
    }

    func testNonTextTypesReturnFalse() {
        let nonTextTypes: [SourceFormat] = [.fileURL, .image]
        for ct in nonTextTypes {
            XCTAssertFalse(card(for: makeItem("", ct)).isTextType,
                           "\(ct) 不应为文本类")
        }
    }

    // MARK: - 多选文本拼接

    private func card(for item: ClipboardItem) -> ClipboardCardView {
        ClipboardCardView(
            item: item,
            isSelected: false,
            cmdBadgeIndex: nil,
            presentation: .card,
            selectedIds: .constant([]),
            onTap: { _ in },
            onPin: { _, _ in },
            onDelete: { _ in }
        )
    }

    private func makeItem(_ content: String, _ type: SourceFormat) -> ClipboardItem {
        ClipboardItem(timestamp: Date(), content: content, sourceFormat: type)
    }

    func testMultiSelectTextOnlyTextTypes() {
        let items = [
            makeItem("Hello", .text),
            makeItem("World", .text),
            makeItem("Test", .rtf),
        ]
        let result = DragPayloadBuilder.multiSelectText(items)
        XCTAssertEqual(result, "Hello\nWorld\nTest", "纯文本类应按换行拼接")
    }

    func testMultiSelectTextSkipsImages() {
        let items = [
            makeItem("Line 1", .text),
            makeItem("/path/to/img.png", .image),
            makeItem("Line 2", .html),
        ]
        let result = DragPayloadBuilder.multiSelectText(items)
        XCTAssertEqual(result, "Line 1\nLine 2", "图片应被跳过")
    }

    func testMultiSelectTextEmptyArray() {
        let result = DragPayloadBuilder.multiSelectText([])
        XCTAssertEqual(result, "", "空数组应返回空字符串")
    }

    func testMultiSelectTextAllImagesReturnsEmpty() {
        let items = [
            makeItem("/a.png", .image),
            makeItem("/b.jpg", .image),
        ]
        let result = DragPayloadBuilder.multiSelectText(items)
        XCTAssertEqual(result, "", "全是图片应返回空")
    }

    func testSingleURLDragProviderExposesURLType() {
        let item = ClipboardItem(
            content: "https://example.com/video",
            sourceFormat: .text,
            tags: ContentTags(isURL: true)
        )

        let provider = DragPayloadBuilder.provider(for: item)

        XCTAssertTrue(provider.registeredTypeIdentifiers.contains("public.url"))
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains("public.utf8-plain-text"))
    }

    func testMultiURLSelectionDragProviderKeepsPlainTextList() {
        let items = [
            ClipboardItem(content: "https://example.com/a", sourceFormat: .text, tags: ContentTags(isURL: true)),
            ClipboardItem(content: "https://example.com/b", sourceFormat: .text, tags: ContentTags(isURL: true)),
        ]

        let provider = DragPayloadBuilder.providerForSelection(items)

        let exp = expectation(description: "plain URL list loaded")
        provider.loadItem(forTypeIdentifier: "public.utf8-plain-text", options: nil) { item, error in
            XCTAssertNil(error)
            if let data = item as? Data {
                XCTAssertEqual(String(data: data, encoding: .utf8), "https://example.com/a\nhttps://example.com/b")
            } else {
                XCTAssertEqual(item as? String, "https://example.com/a\nhttps://example.com/b")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testMultiURLSelectionStillTracksWebURLsForPrimaryURLFlavor() {
        let items = [
            ClipboardItem(content: "https://example.com/a", sourceFormat: .text, tags: ContentTags(isURL: true)),
            ClipboardItem(content: "https://example.com/b", sourceFormat: .text, tags: ContentTags(isURL: true)),
        ]

        XCTAssertEqual(
            DragPayloadBuilder.webURLsForLinkSelection(items).map(\.absoluteString),
            ["https://example.com/a", "https://example.com/b"]
        )
    }

    func testMultiURLSelectionPayloadKeepsTextAndSeparateWebURLs() {
        let items = [
            ClipboardItem(content: "https://example.com/a", sourceFormat: .text, tags: ContentTags(isURL: true)),
            ClipboardItem(content: "https://example.com/b", sourceFormat: .text, tags: ContentTags(isURL: true)),
        ]

        let payload = DragPayloadBuilder.payloadForSelection(items)

        XCTAssertEqual(payload.text, "https://example.com/a\nhttps://example.com/b")
        XCTAssertEqual(payload.webURLs.map(\.absoluteString), ["https://example.com/a", "https://example.com/b"])
        XCTAssertTrue(payload.fileURLs.isEmpty)
    }

    func testMixedURLAndTextSelectionKeepsPlainTextPayload() {
        let items = [
            ClipboardItem(content: "https://example.com/a", sourceFormat: .text, tags: ContentTags(isURL: true)),
            ClipboardItem(content: "plain note", sourceFormat: .text),
        ]

        XCTAssertEqual(
            DragPayloadBuilder.multiSelectText(items),
            "https://example.com/a\nplain note"
        )

        let provider = DragPayloadBuilder.providerForSelection(items)
        let exp = expectation(description: "plain text loaded")
        provider.loadItem(forTypeIdentifier: "public.utf8-plain-text", options: nil) { item, error in
            XCTAssertNil(error)
            if let data = item as? Data {
                XCTAssertEqual(String(data: data, encoding: .utf8), "https://example.com/a\nplain note")
            } else {
                XCTAssertEqual(item as? String, "https://example.com/a\nplain note")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testMultiSelectionIncludesFilePathsAndText() {
        let items = [
            ClipboardItem(content: "/Users/test/movie.mp4", sourceFormat: .fileURL),
            ClipboardItem(content: "plain note", sourceFormat: .text),
        ]

        XCTAssertEqual(
            DragPayloadBuilder.multiSelectText(items),
            "/Users/test/movie.mp4\nplain note"
        )
    }

    func testMultiSelectionSkipsImageOnlyItems() {
        let items = [
            ClipboardItem(content: "/tmp/preview.png", sourceFormat: .image),
            ClipboardItem(content: "plain note", sourceFormat: .text),
        ]

        XCTAssertEqual(DragPayloadBuilder.multiSelectText(items), "plain note")
    }

    func testMultiSelectionPayloadIncludesExistingImageFileURL() throws {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastry-drag-image-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let items = [
            ClipboardItem(content: imageURL.path, sourceFormat: .image),
            ClipboardItem(content: "plain note", sourceFormat: .text),
        ]

        let payload = DragPayloadBuilder.payloadForSelection(items)

        XCTAssertEqual(payload.text, "plain note")
        XCTAssertEqual(payload.fileURLs, [imageURL])
        XCTAssertTrue(payload.webURLs.isEmpty)
    }

    // MARK: - isMultiFile 判断

    func testIsMultiFileTrueForFileURLWithNewline() {
        XCTAssertTrue(card(for: makeItem("/tmp/a.txt\n/tmp/b.txt", .fileURL)).isMultiFile)
    }

    func testIsMultiFileFalseForSingleFileURL() {
        XCTAssertFalse(card(for: makeItem("/tmp/only.txt", .fileURL)).isMultiFile)
    }

    func testIsMultiFileFalseForNonFileURL() {
        for format in [SourceFormat.text, .image] {
            XCTAssertFalse(card(for: makeItem("/tmp/a.txt\n/tmp/b.txt", format)).isMultiFile)
        }
    }

    // MARK: - openableURL 存在性检查

    func testOpenableURLReturnsNilForDeletedFile() {
        let path = NSTemporaryDirectory() + "pastry_test_deleted_\(UUID().uuidString).txt"
        let item = makeItem(path, .fileURL)
        // 文件不存在 → openableURL 应为 nil
        XCTAssertNil(card(for: item).openableURL,
                     "已删除/不存在的文件 openableURL 应为 nil")
    }

    func testOpenableURLReturnsURLForExistingFile() {
        let path = NSTemporaryDirectory() + "pastry_test_exists_\(UUID().uuidString).txt"
        try? "test".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let item = makeItem(path, .fileURL)
        let result = card(for: item).openableURL
        XCTAssertNotNil(result, "存在的文件 openableURL 不应为 nil")
        XCTAssertEqual(result?.path, path)
    }

    func testOpenableURLMultiFileReturnsFirstExisting() {
        let existing = NSTemporaryDirectory() + "pastry_test_multi_1_\(UUID().uuidString).txt"
        let deleted = NSTemporaryDirectory() + "pastry_test_multi_2_\(UUID().uuidString).txt"
        try? "first".write(toFile: existing, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: existing) }

        let item = makeItem("\(existing)\n\(deleted)", .fileURL)
        let result = card(for: item).openableURL
        XCTAssertNotNil(result, "多文件中至少一个存在时应返回第一个存在的")
        XCTAssertEqual(result?.path, existing)
    }

    func testOpenableURLMultiFileAllDeletedReturnsNil() {
        let a = NSTemporaryDirectory() + "pastry_test_allgone_a_\(UUID().uuidString).txt"
        let b = NSTemporaryDirectory() + "pastry_test_allgone_b_\(UUID().uuidString).txt"
        let item = makeItem("\(a)\n\(b)", .fileURL)
        XCTAssertNil(card(for: item).openableURL,
                     "多文件全部删除时 openableURL 应为 nil")
    }

    func testOpenableURLImageType() {
        let path = NSTemporaryDirectory() + "pastry_test_img_\(UUID().uuidString).png"
        try? "fake".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let item = makeItem(path, .image)
        let result = card(for: item).openableURL
        XCTAssertNotNil(result, "存在的图片缓存文件 openableURL 不应为 nil")
    }

    func testOpenableURLImageDeleted() {
        let item = makeItem("/tmp/nonexistent_img.png", .image)
        XCTAssertNil(card(for: item).openableURL,
                     "已删除的图片缓存 openableURL 应为 nil")
    }

    func testOpenableURLForHTTPURL() {
        let item = makeItem("https://example.com", .text)
        let result = card(for: item).openableURL
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.absoluteString, "https://example.com")
    }

    // MARK: - openableURL 对 RTF/HTML 中链接的识别

    func testOpenableURLForBareDomainInText() {
        let item = makeItem("something.com", .text)
        let result = card(for: item).openableURL
        XCTAssertNotNil(result, "裸域名应通过 NSDataDetector 识别")
        XCTAssertEqual(result?.absoluteString, "https://something.com")
    }

    func testOpenableURLForBareDomainInRTF() {
        let item = makeItem("something.com", .rtf)
        let result = card(for: item).openableURL
        XCTAssertNotNil(result, "RTF 中的裸域名应通过 NSDataDetector 识别")
        XCTAssertEqual(result?.absoluteString, "https://something.com")
    }

    func testOpenableURLForBareDomainInHTML() {
        let item = makeItem("something.com", .html)
        let result = card(for: item).openableURL
        XCTAssertNotNil(result, "HTML 中的裸域名应通过 NSDataDetector 识别")
        XCTAssertEqual(result?.absoluteString, "https://something.com")
    }

    func testOpenableURLForFullURLInRTF() {
        let item = makeItem("https://example.com", .rtf)
        let result = card(for: item).openableURL
        XCTAssertNotNil(result, "RTF 中的完整 URL 应可识别")
        XCTAssertEqual(result?.absoluteString, "https://example.com")
    }

    func testOpenableURLForFullURLInHTML() {
        let item = makeItem("https://example.com/path", .html)
        let result = card(for: item).openableURL
        XCTAssertNotNil(result, "HTML 中的完整 URL 应可识别")
        XCTAssertEqual(result?.absoluteString, "https://example.com/path")
    }

    func testOpenableURLReturnsNilForPlainTextInRTF() {
        let item = makeItem("hello world", .rtf)
        XCTAssertNil(card(for: item).openableURL,
                     "RTF 纯文本不应返回 URL")
    }

    func testOpenableURLReturnsNilForPlainTextInHTML() {
        let item = makeItem("<p>Hello</p>", .html)
        XCTAssertNil(card(for: item).openableURL,
                     "HTML 纯文本不含链接不应返回 URL")
    }

    // MARK: - HTTP → HTTPS 升级

    func testHTTPUpgradedToHTTPSForBareDomain() {
        // NSDataDetector 返回 http://something.com → 升级为 https://
        let item = makeItem("example.org", .text)
        let result = card(for: item).openableURL
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.scheme, "https", "裸域名应升级为 https://")
        XCTAssertEqual(result?.absoluteString, "https://example.org")
    }

    func testExplicitHTTPAlsoUpgraded() {
        let item = makeItem("http://example.com", .text)
        let result = card(for: item).openableURL
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.scheme, "https", "显式 http:// 也应升级")
        XCTAssertEqual(result?.absoluteString, "https://example.com")
    }

    func testHTTPSUnchanged() {
        let item = makeItem("https://secure.example.com", .text)
        let result = card(for: item).openableURL
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.scheme, "https")
        XCTAssertEqual(result?.absoluteString, "https://secure.example.com")
    }

}
