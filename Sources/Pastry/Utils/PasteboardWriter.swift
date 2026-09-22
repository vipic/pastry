import Cocoa
import OSLog

enum PasteboardWriteResult: Equatable {
    case written
    case noWritableContent
}

struct PasteboardWriter {
    struct Options {
        var filterMissingFileURLs: Bool
        var includeImageAnnotation: Bool
        var preferOriginalImage: Bool

        static let storeSingle = Options(
            filterMissingFileURLs: false,
            includeImageAnnotation: false,
            preferOriginalImage: false
        )

        static let overlaySingle = Options(
            filterMissingFileURLs: true,
            includeImageAnnotation: true,
            preferOriginalImage: true
        )
    }

    private static let log = Logger(subsystem: "com.nekutai.pastry", category: "pasteboard-writer")
    private static let diagnosticsLog = PastryLogger(category: "pasteboard-writer")

    static func write(
        _ item: ClipboardItem,
        to pasteboard: NSPasteboard = .general,
        options: Options,
        loadFullContent: (ClipboardItem) -> String? = { item in
            DatabaseManager.shared.loadFullContent(id: item.id) ?? item.content
        },
        loadRawFormatData: (ClipboardItem) -> (data: Data?, type: String?)? = { item in
            let result = DatabaseManager.shared.loadRawFormatData(id: item.id)
            return result.data == nil && result.type == nil ? nil : result
        },
        originalImagePath: (String) -> String? = { thumbnailPath in
            ImageCacheManager.shared.originalPath(forThumbnail: thumbnailPath)
        }
    ) async -> PasteboardWriteResult {
        // 先判定「确实有内容可写」再 clearContents：clear 之后才发现写不出去，
        // 会让用户同时失去原剪贴板内容和本次操作（例如文件已被移动的卡片）。
        switch item.sourceFormat {
        case .text:
            let text = loadFullContent(item) ?? item.content
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .written

        case .rtf, .html:
            let text = loadFullContent(item) ?? item.content
            // 优先用内存中的 rawFormatData，否则按需从 DB 加载
            let raw: (data: Data?, type: String?) = {
                if let d = item.rawFormatData, let t = item.rawFormatType { return (d, t) }
                return loadRawFormatData(item) ?? (nil, nil)
            }()
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            if let rawData = raw.data, let typeStr = raw.type {
                pasteboard.setData(rawData, forType: NSPasteboard.PasteboardType(typeStr))
            }
            return .written

        case .fileURL:
            let urls = FileLocationResolver.resolvedURLs(for: item)
            let writableURLs = options.filterMissingFileURLs
                ? urls.filter { FileManager.default.fileExists(atPath: $0.path) }
                : urls
            guard !writableURLs.isEmpty else { return .noWritableContent }
            pasteboard.clearContents()
            pasteboard.writeObjects(writableURLs as [NSURL])
            return .written

        case .image:
            let imagePath: String
            if item.fileBookmarks != nil,
               let movedURL = FileLocationResolver.existingURLs(for: item).first {
                imagePath = movedURL.path
            } else {
                imagePath = options.preferOriginalImage
                    ? (originalImagePath(item.content) ?? item.content)
                    : item.content
            }
            guard let image = await Task.detached(priority: .userInitiated, operation: { () -> NSImage? in
                NSImage(contentsOfFile: imagePath)
            }).value else {
                diagnosticsLog.warning(
                    "无法读取待写入的图片",
                    event: "pasteboard.image_load.failed"
                )
                return .noWritableContent
            }

            pasteboard.clearContents()
            if options.includeImageAnnotation,
               let annotation = item.textAnnotation,
               !annotation.isEmpty {
                writeAnnotatedImage(image, annotation: annotation, to: pasteboard)
            } else {
                pasteboard.writeObjects([image])
            }
            return .written
        }
    }

    static func writePlainText(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func clearSystemClipboard(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("", forType: .string)
        ClipboardMonitor.shared.syncChangeCount()
    }

    private static func writeAnnotatedImage(_ image: NSImage, annotation: String, to pasteboard: NSPasteboard) {
        let attr = NSMutableAttributedString()
        let attachment = NSTextAttachment()
        attachment.image = image
        attr.append(NSAttributedString(attachment: attachment))
        attr.append(NSAttributedString(string: "\n\(annotation)"))

        do {
            let rtfd = try attr.data(
                from: NSRange(location: 0, length: attr.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
            pasteboard.setData(rtfd, forType: .rtfd)
        } catch {
            log.error("RTFD 写入失败: \(error.localizedDescription)")
            diagnosticsLog.error(
                "RTFD 写入失败",
                event: "pasteboard.rtfd_write.failed",
                metadata: ["error": error.localizedDescription]
            )
        }

        pasteboard.setData(image.tiffRepresentation, forType: .tiff)
        pasteboard.setString(annotation, forType: .string)
    }
}
