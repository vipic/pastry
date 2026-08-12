import XCTest
@testable import Pastry

// MARK: - ImageCacheManager 测试套件
// 验证图片双存储（原始数据 + 缩略图 .thumb.png）及粘贴路径推导

final class ImageCacheManagerTests: XCTestCase {

    let manager = ImageCacheManager.shared

    // MARK: - save() 双存储

    /// 保存后同时存在原始数据和 .thumb.png（缩略图）
    func testSaveCreatesBothFiles() throws {
        let originalData = generateTestTIFFData(width: 1200, height: 800)
        let image = NSImage(data: originalData)!

        let thumbPath = manager.save(image: image, data: originalData)
        XCTAssertNotNil(thumbPath, "save() 应返回缩略图路径")
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbPath!), "缩略图文件应存在")

        let origPath = manager.originalPath(forThumbnail: thumbPath!)
        XCTAssertNotNil(origPath, "原始数据路径应存在")
        XCTAssertTrue(FileManager.default.fileExists(atPath: origPath!), "原始数据文件应存在")
    }

    /// 原始数据文件内容与剪贴板读取到的原始 data 一致
    func testOrigFileContainsExactOriginalData() throws {
        let originalData = generateTestTIFFData(width: 1200, height: 800)
        let image = NSImage(data: originalData)!

        let thumbPath = manager.save(image: image, data: originalData)
        let origPath = manager.originalPath(forThumbnail: thumbPath!)
        let savedData = try Data(contentsOf: URL(fileURLWithPath: origPath!))

        XCTAssertEqual(savedData, originalData, "原始数据应逐字节一致")
    }

    /// 缩略图逻辑尺寸不超过 256（点，非像素 — 像素尺寸取决于屏幕 scale）
    func testThumbnailLogicSizeMax256() throws {
        let originalData = generateTestTIFFData(width: 2400, height: 1600)
        let image = NSImage(data: originalData)!

        let thumbPath = manager.save(image: image, data: originalData)!
        let thumb = NSImage(contentsOfFile: thumbPath)!

        XCTAssertLessThanOrEqual(Int(thumb.size.width), 256, "缩略图逻辑宽度 ≤ 256pt")
        XCTAssertLessThanOrEqual(Int(thumb.size.height), 256, "缩略图逻辑高度 ≤ 256pt")
    }

    // MARK: - originalPath(forThumbnail:)

    /// 通过缩略图路径反查原始路径
    func testOriginalPathDerivesCorrectly() throws {
        let originalData = generateTestTIFFData(width: 100, height: 100)
        let image = NSImage(data: originalData)!

        let thumbPath = manager.save(image: image, data: originalData)!
        let origPath = manager.originalPath(forThumbnail: thumbPath)!

        XCTAssertTrue(thumbPath.hasSuffix(".thumb.png"), "缩略图文件扩展名应为 .thumb.png")
        XCTAssertTrue(origPath.hasSuffix(".original.tiff"), "TIFF 原始数据应保留 .tiff 扩展名")

        let thumbStem = URL(fileURLWithPath: thumbPath).deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ".thumb", with: "")
        let origStem = URL(fileURLWithPath: origPath).deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ".original", with: "")
        XCTAssertEqual(thumbStem, origStem, "缩略图和原始数据应共享 UUID stem")
    }

    func testPNGOriginalKeepsPNGExtension() throws {
        let originalData = generateTestPNGData(width: 200, height: 120)
        let image = NSImage(data: originalData)!

        let thumbPath = manager.save(image: image, data: originalData)!
        let origPath = manager.originalPath(forThumbnail: thumbPath)!
        let savedData = try Data(contentsOf: URL(fileURLWithPath: origPath))

        XCTAssertTrue(origPath.hasSuffix(".original.png"), "PNG 原始数据应保存为 .png，而不是 .orig")
        XCTAssertEqual(savedData, originalData, "PNG 原始数据应逐字节一致")
    }

    /// 不存在 .orig 时返回 nil（兼容旧缓存）
    func testOriginalPathReturnsNilWhenNoOrigFile() {
        let nonexistentThumbPath = "/tmp/______nonexistent______.png"
        let result = manager.originalPath(forThumbnail: nonexistentThumbPath)
        XCTAssertNil(result, "无 .orig 文件时应返回 nil")
    }

    // MARK: - 旧缓存兼容

    /// 旧缓存只有 .png 无 .orig 时，originalPath 返回 nil
    func testOldCacheWithoutOrigReturnsNil() throws {
        let originalData = generateTestTIFFData(width: 100, height: 100)
        let image = NSImage(data: originalData)!

        let thumbPath = manager.save(image: image, data: originalData)!
        let origPath = manager.originalPath(forThumbnail: thumbPath)!

        // 模拟删除 .orig 文件（旧缓存场景）
        try FileManager.default.removeItem(atPath: origPath)

        XCTAssertNil(manager.originalPath(forThumbnail: thumbPath), "删除 .orig 后应返回 nil")
    }

    func testOldOrigCacheStillResolves() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastry-image-cache-test-\(UUID().uuidString)", isDirectory: true)
        let manager = ImageCacheManager(cacheDir: dir)
        let thumb = dir.appendingPathComponent("legacy.png")
        let orig = dir.appendingPathComponent("legacy.orig")
        try Data([0x01]).write(to: thumb)
        try Data([0x02]).write(to: orig)

        XCTAssertEqual(manager.originalPath(forThumbnail: thumb.path), orig.path)
        XCTAssertEqual(manager.counterpartURL(for: thumb), orig)
        XCTAssertEqual(manager.counterpartURL(for: orig), thumb)
    }

    func testRepeatedSavesReuseEstimatedCacheSizeWithoutRescanningDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastry-cache-size-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = ImageCacheManager(cacheDir: dir, maxCacheSize: 1_000_000_000)
        let data = generateTestPNGData(width: 40, height: 30)
        let image = try XCTUnwrap(NSImage(data: data))

        XCTAssertNotNil(manager.save(image: image, data: data))
        let first = manager.maintenanceSnapshotForTesting()
        XCTAssertEqual(first.directoryScans, 1)
        XCTAssertNotNil(first.estimatedBytes)

        XCTAssertNotNil(manager.save(image: image, data: data))
        let second = manager.maintenanceSnapshotForTesting()
        XCTAssertEqual(second.directoryScans, 1, "阈值以内的后续保存不应再次枚举缓存目录")
        XCTAssertGreaterThan(second.estimatedBytes ?? 0, first.estimatedBytes ?? 0)
    }

    // MARK: - suggestedFilename

    /// 非缓存路径：沿用原始文件名
    func testSuggestedFilenameUsesOriginalNameForNonCachePath() {
        let name = manager.suggestedFilename(forImagePath: "/tmp/screenshot.png")
        XCTAssertEqual(name, "screenshot.png")
    }

    /// 缓存缩略图路径：统一为 Pastry Image.<ext>
    func testSuggestedFilenameForCachedThumbnail() throws {
        let originalData = generateTestPNGData(width: 80, height: 60)
        let image = NSImage(data: originalData)!
        let thumbPath = try XCTUnwrap(manager.save(image: image, data: originalData))
        let name = manager.suggestedFilename(forImagePath: thumbPath)
        XCTAssertEqual(name, "Pastry Image.png")
    }

    /// 缓存原始文件（.original.png）也映射为 Pastry Image.png
    func testSuggestedFilenameForCachedOriginal() throws {
        let originalData = generateTestPNGData(width: 80, height: 60)
        let image = NSImage(data: originalData)!
        let thumbPath = try XCTUnwrap(manager.save(image: image, data: originalData))
        let origPath = try XCTUnwrap(manager.originalPath(forThumbnail: thumbPath))
        let name = manager.suggestedFilename(forImagePath: origPath)
        XCTAssertTrue(name.hasPrefix("Pastry Image."), name)
        XCTAssertTrue(name.hasSuffix(".png"), name)
    }

    /// Foundation 在不同系统版本上可能用有无末尾斜杠表示同一个目录。
    func testSuggestedFilenameIgnoresDirectoryURLRepresentation() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastry-cache-url-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let cacheWithoutDirectoryHint = URL(
            fileURLWithPath: base.appendingPathComponent("ImageCache").path,
            isDirectory: false
        )
        let manager = ImageCacheManager(cacheDir: cacheWithoutDirectoryHint)
        let cachedFile = cacheWithoutDirectoryHint
            .appendingPathComponent("sample.thumb.png", isDirectory: false)

        XCTAssertNotEqual(
            cachedFile.deletingLastPathComponent().standardizedFileURL,
            cacheWithoutDirectoryHint.standardizedFileURL,
            "回归夹具必须保留 URL 目录表示差异"
        )
        XCTAssertEqual(
            manager.suggestedFilename(forImagePath: cachedFile.path),
            "Pastry Image.png"
        )
    }

    // MARK: - 预览用高清 PNG 生成（orig → TIFF → PNG）

    /// 验证 .orig 数据可转换为 PNG 格式供 Quick Look 预览
    func testOrigDataConvertsToValidPNG() throws {
        let originalData = generateTestTIFFData(width: 2400, height: 1600)
        let image = NSImage(data: originalData)!
        let thumbPath = manager.save(image: image, data: originalData)!
        let origPath = manager.originalPath(forThumbnail: thumbPath)!

        // 模拟 previewItem 中的转换管线
        let origData = try Data(contentsOf: URL(fileURLWithPath: origPath))
        let origImage = NSImage(data: origData)
        XCTAssertNotNil(origImage, "orig 数据应可解码为 NSImage")

        let tiff = origImage!.tiffRepresentation
        XCTAssertNotNil(tiff, "NSImage 应可输出 TIFF")

        let bitmap = NSBitmapImageRep(data: tiff!)
        XCTAssertNotNil(bitmap, "TIFF 应可解码为 bitmap")

        let png = bitmap!.representation(using: .png, properties: [:])
        XCTAssertNotNil(png, "bitmap 应可编码为 PNG")

        // 验证 PNG 是有效图片
        let recovered = NSImage(data: png!)
        XCTAssertNotNil(recovered, "生成的 PNG 应可重新解码")
        XCTAssertEqual(recovered!.size.width, 2400, "宽度应保留")
        XCTAssertEqual(recovered!.size.height, 1600, "高度应保留")
    }

    // MARK: - 帮助函数

    /// 生成测试用 TIFF 数据
    private func generateTestTIFFData(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        image.unlockFocus()
        return image.tiffRepresentation!
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
}
