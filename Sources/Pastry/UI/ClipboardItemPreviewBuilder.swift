import Foundation
import AppKit

/// 卡片 / 键盘 Space 共用的 Quick Look 元数据构建。
enum ClipboardItemPreviewBuilder {

    /// 是否可预览（多文件不可；文件/图片需磁盘存在；文本类始终可）。
    static func canPreview(_ item: ClipboardItem) -> Bool {
        switch item.sourceFormat {
        case .fileURL:
            if item.content.contains("\n") { return false }
            return !FileLocationResolver.existingURLs(for: item).isEmpty
        case .image:
            if item.fileBookmarks != nil,
               !FileLocationResolver.existingURLs(for: item).isEmpty { return true }
            let path = ImageCacheManager.shared.originalPath(forThumbnail: item.content) ?? item.content
            return FileManager.default.fileExists(atPath: path)
        case .text, .rtf, .html:
            return true
        }
    }

    /// 构建 Quick Look 元数据；不可预览时返回 nil。
    static func makeMetadata(for item: ClipboardItem) -> QLPreviewHelper.PreviewMetadata? {
        guard canPreview(item) else { return nil }

        if let url = openableURL(for: item) {
            switch item.sourceFormat {
            case .fileURL:
                let fileName = url.lastPathComponent
                let ext = url.pathExtension.uppercased()
                return QLPreviewHelper.PreviewMetadata(
                    url: url,
                    displayName: fileName,
                    fileType: ext.isEmpty ? L10n["filetype.file"] : ext,
                    infoText: fileName,
                    isLocalFile: true
                )
            case .image:
                let fileName = url.lastPathComponent
                let ext = (fileName as NSString).pathExtension.uppercased()
                let previewURL = imagePreviewURL(for: item, preferred: url)
                return QLPreviewHelper.PreviewMetadata(
                    url: previewURL,
                    displayName: fileName,
                    fileType: ext.isEmpty ? L10n["filetype.image"] : ext,
                    infoText: fileName,
                    isLocalFile: true
                )
            case .text, .rtf, .html:
                let host = url.host ?? ""
                return QLPreviewHelper.PreviewMetadata(
                    url: url,
                    displayName: host,
                    fileType: L10n["filetype.link"],
                    infoText: url.absoluteString,
                    isLocalFile: false
                )
            }
        }

        guard isTextType(item) else { return nil }

        let ext: String
        let typeLabel: String
        switch item.sourceFormat {
        case .rtf:  ext = "rtf";  typeLabel = "RTF"
        case .html: ext = "html"; typeLabel = "HTML"
        default:    ext = "txt";  typeLabel = L10n["filetype.text"]
        }
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastry_preview_\(UUID().uuidString.prefix(8)).\(ext)")
        let fullContent = DatabaseManager.shared.loadFullContent(id: item.id) ?? item.content

        if item.sourceFormat == .rtf, let rawData = item.rawFormatData {
            try? rawData.write(to: tmpFile)
        } else {
            try? fullContent.write(to: tmpFile, atomically: true, encoding: .utf8)
        }

        let charCount = fullContent.count
        let wordCount = fullContent.split { $0.isWhitespace || $0.isNewline }.count
        let lineCount = fullContent.split(separator: "\n", omittingEmptySubsequences: false).count

        return QLPreviewHelper.PreviewMetadata(
            url: tmpFile,
            displayName: String(format: L10n["preview.title"], typeLabel),
            fileType: typeLabel,
            infoText: String(format: L10n["preview.info"], charCount, wordCount, lineCount),
            isLocalFile: true
        )
    }

    // MARK: - Private

    private static func isTextType(_ item: ClipboardItem) -> Bool {
        item.sourceFormat == .text
            || item.sourceFormat == .rtf
            || item.sourceFormat == .html
            || item.tags.isURL
    }

    private static func openableURL(for item: ClipboardItem) -> URL? {
        switch item.sourceFormat {
        case .fileURL:
            return FileLocationResolver.existingURLs(for: item).first
        case .image:
            if item.fileBookmarks != nil,
               let movedURL = FileLocationResolver.existingURLs(for: item).first {
                return movedURL
            }
            let path = ImageCacheManager.shared.originalPath(forThumbnail: item.content) ?? item.content
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        case .text, .rtf, .html:
            return detectedHTTPURL(in: item.content)
        }
    }

    private static func imagePreviewURL(for item: ClipboardItem, preferred url: URL) -> URL {
        guard url.pathExtension == "orig" else { return url }
        guard let origPath = ImageCacheManager.shared.originalPath(forThumbnail: item.content),
              let origData = try? Data(contentsOf: URL(fileURLWithPath: origPath)),
              let origImage = NSImage(data: origData),
              let tiff = origImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return url }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastry_preview_\(UUID().uuidString.prefix(8)).png")
        try? png.write(to: tmp)
        return tmp
    }

    private static func detectedHTTPURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let s = url.scheme, ["http", "https"].contains(s.lowercased()) {
            return DisplayMode.upgradeToHTTPS(url)
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let url = match.url,
              let s = url.scheme,
              ["http", "https"].contains(s.lowercased())
        else { return nil }
        return DisplayMode.upgradeToHTTPS(url)
    }
}
