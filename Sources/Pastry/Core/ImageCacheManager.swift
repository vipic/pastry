import Cocoa
import OSLog

// MARK: - 图片缓存管理器
final class ImageCacheManager: @unchecked Sendable {
    static let shared = ImageCacheManager()

    private let log = Logger(subsystem: "com.nekutai.pastry", category: "image-cache")
    private let diagnosticsLog = PastryLogger(category: "image-cache")
    private let evictionQueue = DispatchQueue(label: "com.nekutai.pastry.image-cache.eviction", qos: .utility)

    /// 缓存磁盘用量上限（超过触发淘汰）
    private let maxCacheSize: Int64
    /// 淘汰后目标磁盘用量
    private let targetCacheSize: Int64

    private let cacheDir: URL
    /// 串行队列维护的近似总量；首次保存或外部清理后才重新扫描目录。
    private var estimatedCacheSize: Int64?
    private var evictionScheduled = false
    private var directoryScanCount = 0

    private convenience init() {
        self.init(cacheDir: AppDirectories.applicationSupportDirectory().appendingPathComponent("ImageCache"))
    }

    init(
        cacheDir: URL,
        maxCacheSize: Int64 = 200 * 1024 * 1024,
        targetCacheSize: Int64 = 150 * 1024 * 1024
    ) {
        self.cacheDir = cacheDir
        self.maxCacheSize = maxCacheSize
        self.targetCacheSize = min(targetCacheSize, maxCacheSize)
        AppDirectories.ensureDirectory(cacheDir, logCategory: "image-cache")
    }

    /// 保存图片：原始数据保留真实格式，另存缩略图（.thumb.png）用于卡片预览。
    /// 返回缩略图路径（向后兼容 ClipboardItem.content）。
    func save(image: NSImage, data: Data) -> String? {
        let uuid = UUID().uuidString
        let originalExtension = Self.originalExtension(for: data)
        let thumbFilename = "\(uuid).thumb.png"
        let origFilename = originalExtension == "orig"
            ? "\(uuid).orig"
            : "\(uuid).original.\(originalExtension)"
        let thumbURL = cacheDir.appendingPathComponent(thumbFilename)
        let origURL = cacheDir.appendingPathComponent(origFilename)

        // 1. 保存原始数据（保持剪贴板原有格式，TIFF/PNG）
        do {
            try data.write(to: origURL)
        } catch {
            log.error("原始图片写入失败: \(error.localizedDescription)")
            diagnosticsLog.error(
                "原始图片缓存写入失败",
                event: "image_cache.original_write.failed",
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }

        // 2. 生成并保存缩略图（用于卡片预览）
        let thumb = thumbnail(from: image, maxSize: NSSize(width: 256, height: 256))
        guard let thumbData = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: thumbData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            try? FileManager.default.removeItem(at: origURL)
            diagnosticsLog.error(
                "无法生成图片缩略图",
                event: "image_cache.thumbnail_encode.failed"
            )
            return nil
        }
        do {
            try pngData.write(to: thumbURL)
        } catch {
            try? FileManager.default.removeItem(at: origURL)
            diagnosticsLog.error(
                "图片缩略图写入失败",
                event: "image_cache.thumbnail_write.failed",
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }

        scheduleEviction(addedBytes: Int64(data.count + pngData.count))
        return thumbURL.path
    }

    private func scheduleEviction(addedBytes: Int64) {
        evictionQueue.async { [weak self] in
            guard let self else { return }
            if let estimatedCacheSize {
                self.estimatedCacheSize = estimatedCacheSize + addedBytes
            } else {
                self.estimatedCacheSize = self.cacheFileInfos().totalSize
            }

            guard let estimatedCacheSize = self.estimatedCacheSize,
                  estimatedCacheSize > self.maxCacheSize,
                  !self.evictionScheduled
            else { return }
            self.evictionScheduled = true

            // StoreManager 限定 @MainActor；只在真正越过阈值时采集收藏路径。
            Task { @MainActor in
                let pinned = Set(StoreManager.shared.items.filter(\.isPinned)
                    .filter { $0.sourceFormat == .image || $0.sourceFormat == .fileURL }
                    .map(\.content))
                self.evictionQueue.async {
                    self.estimatedCacheSize = self.evictIfNeeded(pinnedPaths: pinned)
                    self.evictionScheduled = false
                }
            }
        }
    }

    /// 从缩略图路径推导原始图片路径（用于粘贴/拖拽/打开时读取高清数据）
    func originalPath(forThumbnail thumbnailPath: String) -> String? {
        let id = cacheID(for: URL(fileURLWithPath: thumbnailPath))
        return originalCandidates(forCacheID: id)
            .first { FileManager.default.fileExists(atPath: $0.path) }?
            .path
    }

    func suggestedFilename(forImagePath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        guard isCachedFile(url) else { return url.lastPathComponent }
        let ext = url.pathExtension.isEmpty || url.pathExtension == "orig" ? "png" : url.pathExtension
        return "Pastry Image.\(ext)"
    }

    /// 配对文件路径：thumbnail ↔ original，兼容旧缓存（.png ↔ .orig）
    func counterpartURL(for url: URL) -> URL? {
        let id = cacheID(for: url)
        if isThumbnailURL(url) {
            return originalCandidates(forCacheID: id)
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }
        if isOriginalURL(url) {
            return thumbnailCandidates(forCacheID: id)
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }
        return nil
    }

    /// LRU 磁盘淘汰：超过 maxCacheSize 时按修改时间删除最旧文件，直到低于 targetCacheSize。
    /// 跳过被收藏（pinned）条目引用的文件，其余按 LRU 清理。
    private func evictIfNeeded(pinnedPaths: Set<String>) -> Int64 {
        let fm = FileManager.default
        var (totalSize, fileInfos) = cacheFileInfos()

        guard totalSize > maxCacheSize else { return totalSize }

        // 按修改时间升序（最旧 → 最新）
        fileInfos.sort { $0.modDate < $1.modDate }

        for info in fileInfos {
            guard totalSize > targetCacheSize else { break }
            // 跳过被收藏条目引用的文件（防止卡片显示破损图标）
            let thumbPath = thumbnailPath(forCachedFile: info.url)
            if let tp = thumbPath, pinnedPaths.contains(tp) { continue }
            do {
                try fm.removeItem(at: info.url)
                totalSize -= info.size
                // 同时清理配对文件，兼容新旧缓存命名。
                if let c = counterpartURL(for: info.url),
                   let cSize = (try? fm.attributesOfItem(atPath: c.path)[.size] as? Int64) {
                    try? fm.removeItem(at: c)
                    totalSize -= cSize
                }
            } catch {
                // 无法删除的文件跳过，继续处理下一个
            }
        }
        return totalSize
    }

    private func cacheFileInfos() -> (
        totalSize: Int64,
        files: [(url: URL, size: Int64, modDate: Date)]
    ) {
        directoryScanCount += 1
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, []) }

        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, size: Int64, modDate: Date)] = []
        for file in files {
            guard let attrs = try? file.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            ), let size = attrs.fileSize.map(Int64.init) else { continue }
            totalSize += size
            fileInfos.append((file, size, attrs.contentModificationDate ?? .distantPast))
        }
        return (totalSize, fileInfos)
    }

    /// 清理孤儿缓存文件：删除数据库中已不存在图片条目的缩略图和原始文件对。
    func cleanupOrphans(activePaths: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }

        var removed = 0
        for file in files where isThumbnailURL(file) {
            guard !activePaths.contains(file.path) else { continue }
            try? FileManager.default.removeItem(at: file)
            if let c = counterpartURL(for: file) {
                try? FileManager.default.removeItem(at: c)
            }
            removed += 1
        }
        if removed > 0 {
            log.info("清理了 \(removed) 个孤儿图片缓存")
            diagnosticsLog.info(
                "孤儿图片缓存清理完成",
                event: "image_cache.orphans.cleaned",
                metadata: ["removed_count": String(removed)]
            )
        }
        evictionQueue.async { [weak self] in
            self?.estimatedCacheSize = nil
        }
    }

    func maintenanceSnapshotForTesting() -> (estimatedBytes: Int64?, directoryScans: Int) {
        evictionQueue.sync { (estimatedCacheSize, directoryScanCount) }
    }

    private func thumbnail(from image: NSImage, maxSize: NSSize) -> NSImage {
        let ratio = min(maxSize.width / max(image.size.width, 1),
                        maxSize.height / max(image.size.height, 1))
        let newSize = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        return NSImage(size: newSize, flipped: false) { rect in
            image.draw(in: rect,
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .copy, fraction: 1.0)
            return true
        }
    }

    private static func originalExtension(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00])
            || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "tiff"
        }
        if bytes.count >= 12,
           String(bytes: bytes[4..<12], encoding: .ascii)?.hasPrefix("ftyp") == true {
            return "heic"
        }
        return "orig"
    }

    private func cacheID(for url: URL) -> String {
        var stem = url.deletingPathExtension().lastPathComponent
        if stem.hasSuffix(".thumb") {
            stem.removeLast(".thumb".count)
        } else if stem.hasSuffix(".original") {
            stem.removeLast(".original".count)
        }
        return stem
    }

    private func thumbnailCandidates(forCacheID id: String) -> [URL] {
        [
            cacheDir.appendingPathComponent("\(id).thumb.png"),
            cacheDir.appendingPathComponent("\(id).png"),
        ]
    }

    private func originalCandidates(forCacheID id: String) -> [URL] {
        [
            "png", "jpg", "jpeg", "gif", "tiff", "heic", "heif", "webp", "orig",
        ].map { ext in
            ext == "orig"
                ? cacheDir.appendingPathComponent("\(id).orig")
                : cacheDir.appendingPathComponent("\(id).original.\(ext)")
        }
    }

    private func isCachedFile(_ url: URL) -> Bool {
        // URL equality also compares directory representation details such as a
        // trailing slash. Those details vary across macOS/Foundation versions,
        // even when both URLs point at the same filesystem directory.
        url.deletingLastPathComponent().standardizedFileURL.path
            == cacheDir.standardizedFileURL.path
    }

    private func isThumbnailURL(_ url: URL) -> Bool {
        guard isCachedFile(url) else { return false }
        let stem = url.deletingPathExtension().lastPathComponent
        if stem.hasSuffix(".original") { return false }
        if stem.hasSuffix(".thumb") { return true }
        return url.pathExtension == "png"
    }

    private func isOriginalURL(_ url: URL) -> Bool {
        guard isCachedFile(url) else { return false }
        let stem = url.deletingPathExtension().lastPathComponent
        return url.pathExtension == "orig" || stem.hasSuffix(".original")
    }

    private func thumbnailPath(forCachedFile url: URL) -> String? {
        guard isCachedFile(url) else { return nil }
        if isThumbnailURL(url) { return url.path }
        if isOriginalURL(url) {
            let id = cacheID(for: url)
            return thumbnailCandidates(forCacheID: id)
                .first { FileManager.default.fileExists(atPath: $0.path) }?
                .path
        }
        return nil
    }
}
