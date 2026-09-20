import XCTest
@testable import Pastry

// MARK: - ClipboardMonitor 测试套件
// 验证剪贴板格式读取（微信/QQ 自定义类型等）
// 所有剪贴板操作使用独立 pasteboard，不触及系统剪贴板

final class ClipboardMonitorTests: XCTestCase {

    /// 创建测试用独立 pasteboard
    private func makeTestPasteboard(_ name: String) -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("test.hermes.pastry.\(name)"))
    }

    // MARK: - TencentAttributeStringType plist 解析

    /// 标准 Tencent plist：图片 + 文字混合
    func testTencentPlistMixedContent() throws {
        let plist: [[String: Any]] = [
            ["TencentElementType": 1, "TencentElementValue": "/tmp/img.png"],
            ["TencentElementType": 11, "TencentElementValue": "这是文字内容"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        let pb = makeTestPasteboard("tencentMixed")
        pb.setData(data, forType: NSPasteboard.PasteboardType("TencentAttributeStringType"))

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertEqual(text, "这是文字内容")
    }

    /// 只有图片没有文字
    func testTencentPlistImageOnly() throws {
        let plist: [[String: Any]] = [
            ["TencentElementType": 1, "TencentElementValue": "/tmp/img.png"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        let pb = makeTestPasteboard("tencentImageOnly")
        pb.setData(data, forType: NSPasteboard.PasteboardType("TencentAttributeStringType"))

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertNil(text)
    }

    /// 多条文字拼接
    func testTencentPlistMultipleTexts() throws {
        let plist: [[String: Any]] = [
            ["TencentElementType": 11, "TencentElementValue": "第一段"],
            ["TencentElementType": 1, "TencentElementValue": "/tmp/img.png"],
            ["TencentElementType": 11, "TencentElementValue": "第二段"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        let pb = makeTestPasteboard("tencentMultiple")
        pb.setData(data, forType: NSPasteboard.PasteboardType("TencentAttributeStringType"))

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertEqual(text, "第一段第二段")
    }

    /// 空数组
    func testTencentPlistEmpty() throws {
        let plist: [[String: Any]] = []
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        let pb = makeTestPasteboard("tencentEmpty")
        pb.setData(data, forType: NSPasteboard.PasteboardType("TencentAttributeStringType"))

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertNil(text)
    }

    /// 无 TencentAttributeStringType 数据
    func testTencentPlistNotPresent() {
        let pb = makeTestPasteboard("tencentNotPresent")
        pb.setString("普通文字", forType: .string)

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertNil(text)
    }

    // MARK: - URL 语义标记

    func testPlainTextBilibiliURLIsTaggedAsLink() {
        let pb = makeTestPasteboard("plainBilibiliURL")
        pb.clearContents()
        pb.setString("https://www.bilibili.com/v/popular/rank/ent", forType: .string)

        let item = ClipboardMonitor.readTextForTesting(from: pb)

        XCTAssertEqual(item?.sourceFormat, .text)
        XCTAssertTrue(item?.tags.isURL ?? false, "纯文本 bilibili URL 应被标记为链接")
    }

    func testHTMLBilibiliURLIsTaggedAsLink() {
        let url = "https://www.bilibili.com/v/popular/rank/ent"
        let html = "<html><body><a href=\"\(url)\">\(url)</a></body></html>"
        let pb = makeTestPasteboard("htmlBilibiliURL")
        pb.clearContents()
        pb.setData(Data(html.utf8), forType: .html)

        let item = ClipboardMonitor.readHTMLForTesting(from: pb)

        XCTAssertEqual(item?.sourceFormat, .html)
        XCTAssertEqual(item?.content.trimmingCharacters(in: .whitespacesAndNewlines), url)
        XCTAssertTrue(item?.tags.isURL ?? false, "HTML 中只有 URL 文本时应展示为链接卡片")
    }

    func testRTFBilibiliURLIsTaggedAsLink() throws {
        let url = "https://www.bilibili.com/v/popular/rank/ent"
        let attr = NSAttributedString(string: url)
        let data = try attr.data(
            from: NSRange(location: 0, length: attr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let pb = makeTestPasteboard("rtfBilibiliURL")
        pb.clearContents()
        pb.setData(data, forType: .rtf)

        let item = ClipboardMonitor.readRTFForTesting(from: pb)

        XCTAssertEqual(item?.sourceFormat, .rtf)
        XCTAssertEqual(item?.content, url)
        XCTAssertTrue(item?.tags.isURL ?? false, "RTF 中只有 URL 文本时应展示为链接卡片")
    }

    // MARK: - ContentSegment Codable

    func testContentSegmentTextCodableRoundTrip() throws {
        let seg = ContentSegment.text("hello world")
        let data = try JSONEncoder().encode(seg)
        let decoded = try JSONDecoder().decode(ContentSegment.self, from: data)
        XCTAssertEqual(decoded, seg)
        XCTAssertEqual(decoded.textValue, "hello world")
        XCTAssertNil(decoded.imageURL)
    }

    func testContentSegmentImageCodableRoundTrip() throws {
        let seg = ContentSegment.image(url: "https://example.com/img.png")
        let data = try JSONEncoder().encode(seg)
        let decoded = try JSONDecoder().decode(ContentSegment.self, from: data)
        XCTAssertEqual(decoded, seg)
        XCTAssertEqual(decoded.imageURL, "https://example.com/img.png")
        XCTAssertNil(decoded.textValue)
    }

    func testContentSegmentArrayCodableRoundTrip() throws {
        let segs: [ContentSegment] = [
            .text("段落一"),
            .image(url: "https://a.com/1.png"),
            .text("段落二"),
            .image(url: "https://a.com/2.png"),
        ]
        let data = try JSONEncoder().encode(segs)
        let decoded = try JSONDecoder().decode([ContentSegment].self, from: data)
        XCTAssertEqual(decoded, segs)
    }

    // MARK: - extractOrderedSegments

    func testSegmentsImageFirstThenText() {
        let html = "<img src='https://a.com/pic.png'><p>后面的文字</p>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].imageURL, "https://a.com/pic.png")
        XCTAssertEqual(segs[1].textValue, "后面的文字")
    }

    func testSegmentsTextFirstThenImage() {
        let html = "<p>前面的文字</p><img src='https://a.com/pic.png'>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].textValue, "前面的文字")
        XCTAssertEqual(segs[1].imageURL, "https://a.com/pic.png")
    }

    func testSegmentsTextOnly() {
        let html = "<p>只有文字没有图</p>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertTrue(segs.isEmpty)
    }

    func testSegmentsImageOnly() {
        let html = "<img src='https://a.com/pic.png'>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].imageURL, "https://a.com/pic.png")
    }

    func testSegmentsDataURIFiltered() {
        let html = "<img src='data:image/png;base64,abc'><p>data URI 应被过滤，只剩文字走 textPreview</p>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertTrue(segs.isEmpty)
    }

    func testSegmentsMultipleImagesInterleaved() {
        let html = "<p>开头</p><img src='https://a.com/1.png'><p>中间</p><img src='https://a.com/2.png'><p>结尾</p>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertEqual(segs.count, 5)
        XCTAssertEqual(segs[0].textValue, "开头")
        XCTAssertEqual(segs[1].imageURL, "https://a.com/1.png")
        XCTAssertEqual(segs[2].textValue, "中间")
        XCTAssertEqual(segs[3].imageURL, "https://a.com/2.png")
        XCTAssertEqual(segs[4].textValue, "结尾")
    }

    func testSegmentsDuplicateURLFiltered() {
        let html = "<img src='https://a.com/pic.png'><img src='https://a.com/pic.png'><p>重复图片应去重</p>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].imageURL, "https://a.com/pic.png")
        XCTAssertEqual(segs[1].textValue, "重复图片应去重")
    }

    func testSegmentsRelativeURLResolved() {
        let html = "<img src='/images/pic.png'><p>文字</p>"
        let source = URL(string: "https://example.com/blog/post.html")!
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: source)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].imageURL, "https://example.com/images/pic.png")
        XCTAssertEqual(segs[1].textValue, "文字")
    }

    func testSegmentsMaxFiveImages() {
        let html = (0..<7).map { i in "<img src='https://a.com/\(i).png'>" }.joined()
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        let imageCount = segs.filter { $0.imageURL != nil }.count
        XCTAssertEqual(imageCount, 5)
    }

    // MARK: - readFileURLs isFileURL 过滤

    /// pasteboard 上只有图片文件 → 应识别为 image（优先于 fileURL）
    func testFileURLsOnlyFileScheme() {
        let pb = makeTestPasteboard("fileURLsOnly")
        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: "/Users/test/photo.png") as NSURL])
        let item = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.sourceFormat, .image)
        XCTAssertEqual(item?.content, "/Users/test/photo.png")
    }

    /// 多个图片文件 → 仍归为 image
    func testMultipleImageFilesClassifiedAsImage() {
        let pb = makeTestPasteboard("multiImages")
        pb.clearContents()
        let urls = [
            URL(fileURLWithPath: "/tmp/a.jpg") as NSURL,
            URL(fileURLWithPath: "/tmp/b.png") as NSURL,
        ]
        pb.writeObjects(urls)
        let item = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.sourceFormat, .image)
        XCTAssertTrue(item?.content.contains("\n") ?? false, "多个文件应用换行分隔")
    }

    /// 非图片文件 → 仍归为 fileURL
    func testNonImageFileClassifiedAsFileURL() {
        let pb = makeTestPasteboard("nonImageFile")
        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: "/tmp/report.pdf") as NSURL])
        let item = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.sourceFormat, .fileURL)
    }

    /// 混合：图片 + 非图片 → 归为 fileURL（不能全归图片）
    func testMixedImageAndNonImageClassifiedAsFileURL() {
        let pb = makeTestPasteboard("mixedFiles")
        pb.clearContents()
        let urls = [
            URL(fileURLWithPath: "/tmp/photo.jpg") as NSURL,
            URL(fileURLWithPath: "/tmp/doc.txt") as NSURL,
        ]
        pb.writeObjects(urls)
        let item = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.sourceFormat, .fileURL)
    }

    /// pasteboard 上只有 web URL（模拟 Handoff 同步） → 不应识别为 fileURL
    func testFileURLsHandoffWebURL() {
        let pb = makeTestPasteboard("fileURLsHandoff")
        pb.clearContents()
        pb.writeObjects([URL(string: "https://example.com/article")! as NSURL])
        let item = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNil(item, "Handoff 同步的 web URL 不应被误判为 fileURL")
    }

    /// pasteboard 上同时有 file:// 和 http:// URL → 只保留 file://
    func testFileURLsMixedSchemes() {
        let pb = makeTestPasteboard("fileURLsMixed")
        pb.clearContents()
        let fileURL = URL(fileURLWithPath: "/tmp/actual-file.pdf") as NSURL
        let webURL = URL(string: "https://example.com/wrong")! as NSURL
        pb.writeObjects([fileURL, webURL])
        let item = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.sourceFormat, .fileURL)
        XCTAssertEqual(item?.content, "/tmp/actual-file.pdf")
    }

    func testCopiedFileStillResolvesAfterFinderMove() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastry-moved-file-\(UUID().uuidString)")
        let destinationDirectory = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("report.txt")
        try "content".write(to: originalURL, atomically: true, encoding: .utf8)
        let pb = makeTestPasteboard("movedFile")
        pb.clearContents()
        pb.writeObjects([originalURL as NSURL])

        let item = try XCTUnwrap(ClipboardMonitor.readFileURLsForTesting(from: pb))
        let movedURL = destinationDirectory.appendingPathComponent(originalURL.lastPathComponent)
        try FileManager.default.moveItem(at: originalURL, to: movedURL)

        XCTAssertEqual(FileLocationResolver.existingURLs(for: item).map(\.path), [movedURL.path])
        XCTAssertEqual(ClipboardItemPreviewBuilder.makeMetadata(for: item)?.url.path, movedURL.path)
    }

    func testImageDataPrefersPNGOverTIFF() {
        let pb = makeTestPasteboard("imagePrefersPNG")
        pb.clearContents()

        let pngData = generateTestPNGData(width: 12, height: 8)
        let tiffData = generateTestTIFFData(width: 12, height: 8)
        pb.setData(tiffData, forType: .tiff)
        pb.setData(pngData, forType: .png)

        let result = ClipboardMonitor.readImageDataForTesting(from: pb)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.1, pngData, "同时存在 PNG/TIFF 时应优先保留 PNG 原始数据")
    }

    // MARK: - 排除名单（bundleID 过滤）

    func testExcludedBundleIDIsBlocked() {
        let testBundleID = "com.test.excluded-app"
        UserDefaults.standard.set([testBundleID], forKey: UserDefaultsKeys.excludedBundleIDs)
        defer { UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.excludedBundleIDs) }

        XCTAssertTrue(ClipboardMonitor.isBundleIDExcludedForTesting(testBundleID),
                      "排除名单中的 bundleID 应返回 true")
    }

    func testNonExcludedBundleIDIsAllowed() {
        let testBundleID = "com.test.normal-app"
        UserDefaults.standard.set(["com.test.excluded-app"], forKey: UserDefaultsKeys.excludedBundleIDs)
        defer { UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.excludedBundleIDs) }

        XCTAssertFalse(ClipboardMonitor.isBundleIDExcludedForTesting(testBundleID),
                       "未在排除名单中的 bundleID 应返回 false")
    }

    func testEmptyExcludedListAllowsAll() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.excludedBundleIDs)
        XCTAssertFalse(ClipboardMonitor.isBundleIDExcludedForTesting("com.1password.1password"),
                       "排除名单为空时所有 App 都应允许")
    }

    // MARK: - Pasteboard 类型过滤

    /// ConcealedType 应被检测到
    func testDetectsConcealedType() {
        let pb = makeTestPasteboard("concealedType")
        pb.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        pb.setString("secret", forType: .string)
        XCTAssertTrue(ClipboardMonitor.hasConcealedTypeForTesting(from: pb),
                      "含 ConcealedType 的 pasteboard 应返回 true")
    }

    /// 无 ConcealedType 的普通剪贴板
    func testNoConcealedTypeOnNormalPasteboard() {
        let pb = makeTestPasteboard("normalTypes")
        pb.declareTypes([.string], owner: nil)
        pb.setString("hello", forType: .string)
        XCTAssertFalse(ClipboardMonitor.hasConcealedTypeForTesting(from: pb),
                       "普通 pasteboard 不应被 ConcealedType 过滤")
    }

    /// 1Password 自定义类型检测
    func testDetects1PasswordType() {
        let pb = makeTestPasteboard("onePassword")
        pb.declareTypes([.string, NSPasteboard.PasteboardType("com.agilebits.onepassword")], owner: nil)
        pb.setString("username", forType: .string)
        XCTAssertTrue(ClipboardMonitor.has1PasswordTypeForTesting(from: pb),
                      "含 com.agilebits.onepassword 的 pasteboard 应返回 true")
    }

    /// 无 1Password 标记的普通剪贴板
    func testNo1PasswordTypeOnNormalPasteboard() {
        let pb = makeTestPasteboard("no1pType")
        pb.declareTypes([.string], owner: nil)
        pb.setString("hello", forType: .string)
        XCTAssertFalse(ClipboardMonitor.has1PasswordTypeForTesting(from: pb),
                       "普通 pasteboard 不应被识别为 1Password")
    }

    private func generateTestTIFFData(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        image.unlockFocus()
        return image.tiffRepresentation!
    }

    private func generateTestPNGData(width: Int, height: Int) -> Data {
        let bitmap = NSBitmapImageRep(data: generateTestTIFFData(width: width, height: height))!
        return bitmap.representation(using: .png, properties: [:])!
    }
}
