import Cocoa

extension ClipboardMonitor {
    // MARK: - 各格式读取器

    func readText(from pb: NSPasteboard, appName: String?, isHandoff: Bool = false) -> ClipboardItem? {
        // 标准纯文本
        if let text = pb.string(forType: .string), !text.isEmpty {
            let isURL = isPlainURL(text)
            return ClipboardItem(content: text, sourceFormat: .text, tags: ContentTags(isURL: isURL), appName: appName, isHandoff: isHandoff)
        }
        // 微信/QQ 自定义富文本（TencentAttributeStringType plist）
        if let text = readTencentText(from: pb), !text.isEmpty {
            let isURL = isPlainURL(text)
            return ClipboardItem(content: text, sourceFormat: .text, tags: ContentTags(isURL: isURL), appName: appName, isHandoff: isHandoff)
        }
        return nil
    }

    /// 检测纯文本是否为 URL（http/https），用于回退到 readText 时将链接归为 .url 类型
    private func isPlainURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased())
        else { return false }
        return true
    }

    /// 微信/QQ 剪贴板自定义类型：二进制 plist 数组，元素含 TencentElementType(11=文本) + TencentElementValue
    private func readTencentText(from pb: NSPasteboard) -> String? {
        let tencentType = NSPasteboard.PasteboardType("TencentAttributeStringType")
        guard let data = pb.data(forType: tencentType),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]]
        else { return nil }
        let texts = plist.compactMap { dict -> String? in
            guard let type = dict["TencentElementType"] as? Int, type == 11,
                  let value = dict["TencentElementValue"] as? String
            else { return nil }
            return value
        }
        let combined = texts.joined()
        return combined.isEmpty ? nil : combined
    }

    func readRTF(from pb: NSPasteboard, appName: String?, isHandoff: Bool = false) -> ClipboardItem? {
        guard let data = pb.data(forType: .rtf) else { return nil }
        return readRTFData(data, appName: appName, isHandoff: isHandoff)
    }

    func readRTFData(_ data: Data, appName: String?, isHandoff: Bool = false) -> ClipboardItem? {
        guard let attr = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }
        return ClipboardItem(
            content: attr.string,
            sourceFormat: .rtf,
            tags: ContentTags(isURL: isPlainURL(attr.string)),
            appName: appName,
            isHandoff: isHandoff,
            rawFormatData: data,
            rawFormatType: "public.rtf"
        )
    }

    func readHTML(from pb: NSPasteboard, appName: String?, isHandoff: Bool = false) -> ClipboardItem? {
        guard let data = pb.data(forType: .html),
              let html = String(data: data, encoding: .utf8)
        else { return nil }
        return readHTMLData(data, html: html, sourceURL: readChromiumSourceURL(from: pb), appName: appName, isHandoff: isHandoff)
    }

    func readHTMLData(_ data: Data, html: String, sourceURL: URL?, appName: String?, isHandoff: Bool = false) -> ClipboardItem? {
        // 提取纯文本
        var content: String
        if let attr = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil) {
            content = attr.string
        } else {
            content = html
        }

        // 提取 HTML 图文混排的有序段
        let segments = extractOrderedSegments(from: html, sourceURL: sourceURL)

        return ClipboardItem(
            content: content,
            sourceFormat: .html,
            tags: ContentTags(isURL: isPlainURL(content), hasSegments: !segments.isEmpty),
            appName: appName,
            isHandoff: isHandoff,
            segments: segments.isEmpty ? nil : segments,
            rawFormatData: data,
            rawFormatType: "public.html"
        )
    }

    /// 从 Chromium 剪贴板自定义字段中读取源页面 URL
    func readChromiumSourceURL(from pb: NSPasteboard) -> URL? {
        let sourceType = NSPasteboard.PasteboardType("org.chromium.source-url")
        guard let data = pb.data(forType: sourceType),
              let urlStr = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return URL(string: urlStr)
    }

    /// 解析 HTML 为有序图文段，保留原始 DOM 顺序
    private func extractOrderedSegments(from html: String, sourceURL: URL?) -> [ContentSegment] {
        guard let imgRegex = try? NSRegularExpression(
            pattern: "<img[^>]+src=[\"']([^\"']+)[\"'][^>]*>",
            options: .caseInsensitive
        ) else { return [] }

        let nsRange = NSRange(html.startIndex..., in: html)
        let imgMatches = imgRegex.matches(in: html, range: nsRange)

        // 收集所有 <img> 位置 + 解析后的 URL，最多 5 张，去重
        var imgEntries: [(range: NSRange, url: String)] = []
        var seen = Set<String>()
        for match in imgMatches.prefix(5) {
            guard let captureRange = Range(match.range(at: 1), in: html) else { continue }
            let src = String(html[captureRange])
            guard !src.hasPrefix("data:") else { continue }

            let resolved: String
            if let source = sourceURL, let r = URL(string: src, relativeTo: source) {
                resolved = r.absoluteString
            } else if URL(string: src) != nil {
                resolved = src
            } else { continue }

            guard !seen.contains(resolved) else { continue }
            seen.insert(resolved)
            imgEntries.append((match.range, resolved))
        }

        guard !imgEntries.isEmpty else { return [] }

        // 按位置排序
        imgEntries.sort { $0.range.location < $1.range.location }

        // 在 HTML 中切分：文字段（img 之间）→ 图片段 → 文字段 → ...
        var segments: [ContentSegment] = []
        var cursor = html.startIndex

        for entry in imgEntries {
            guard let imgStart = Range(entry.range, in: html)?.lowerBound else { continue }

            // 提取 img 之前的文字
            if cursor < imgStart {
                let rawText = String(html[cursor..<imgStart])
                let clean = stripHTMLTags(rawText).trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    // 与前一个文字段合并
                    if case .text(let prev) = segments.last {
                        segments[segments.count - 1] = .text(prev + clean)
                    } else {
                        segments.append(.text(clean))
                    }
                }
            }

            // 插入图片段
            segments.append(.image(url: entry.url))

            // 移动游标到 img 之后
            cursor = Range(entry.range, in: html)?.upperBound ?? cursor
        }

        // img 之后的尾部文字
        if cursor < html.endIndex {
            let rawText = String(html[cursor..<html.endIndex])
            let clean = stripHTMLTags(rawText).trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                if case .text(let prev) = segments.last {
                    segments[segments.count - 1] = .text(prev + clean)
                } else {
                    segments.append(.text(clean))
                }
            }
        }

        return segments
    }

    /// 去除 HTML 标签和实体，保留纯文本
    private func stripHTMLTags(_ html: String) -> String {
        // 先处理常见实体
        var text = html
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        // 去除标签
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else { return text }
        text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        return text
    }

    /// 仅读取剪贴板图片数据和 NSImage（主线程安全，轻量操作）。
    /// 缩略图生成、编码和磁盘写入已移至后台队列。
    func readImageData(from pb: NSPasteboard) -> (NSImage, Data)? {
        guard let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
              let image = NSImage(data: data)
        else { return nil }
        return (image, data)
    }

    func readFileURLs(from pb: NSPasteboard, appName: String?, isHandoff: Bool = false) -> ClipboardItem? {
        var paths: [String] = []

        // 1. NSFilenamesPboardType：Finder / NSPasteboard 多文件写入的标准格式
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let filenames = pb.propertyList(forType: filenamesType) as? [String], !filenames.isEmpty {
            paths = filenames
        }

        // 2. 逐 item 读 public.file-url（NSPasteboardItem.setString 写入的单文件格式）
        if paths.isEmpty, let items = pb.pasteboardItems, !items.isEmpty {
            for item in items {
                if let urlStr = item.string(forType: .fileURL),
                   let url = URL(string: urlStr),
                   url.isFileURL {
                    paths.append(url.path)
                }
            }
        }

        // 3. 回退：readObjects(forClasses:)（向后兼容）
        if paths.isEmpty {
            guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                  !urls.isEmpty
            else { return nil }
            let fileURLs = urls.filter { $0.isFileURL }
            guard !fileURLs.isEmpty else { return nil }
            paths = fileURLs.map(\.path)
        }

        guard !paths.isEmpty else { return nil }
        let content = paths.joined(separator: "\n")
        let fileBookmarks = FileLocationResolver.makeBookmarks(for: paths)

        // 所有文件都是图片 → 归为 .image
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "heif"]
        let allImages = paths.allSatisfy { p in
            imageExtensions.contains(URL(fileURLWithPath: p).pathExtension.lowercased())
        }
        if allImages {
            return ClipboardItem(
                content: content,
                sourceFormat: .image,
                appName: appName,
                isHandoff: isHandoff,
                fileBookmarks: fileBookmarks
            )
        }

        return ClipboardItem(
            content: content,
            sourceFormat: .fileURL,
            appName: appName,
            isHandoff: isHandoff,
            fileBookmarks: fileBookmarks
        )
    }

    /// 检测剪贴板中的 URL 链接（http/https），优于纯文本捕获
    func readURL(from pb: NSPasteboard, appName: String?, isHandoff: Bool = false) -> ClipboardItem? {
        // 先用 NSURL 类读取，只保留 http/https 的远程 URL
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty
        else { return nil }
        let webURLs = urls.filter { $0.scheme == "http" || $0.scheme == "https" }
        guard !webURLs.isEmpty else { return nil }
        let urlStrings = webURLs.map(\.absoluteString).joined(separator: "\n")
        return ClipboardItem(content: urlStrings, sourceFormat: .text, tags: ContentTags(isURL: true), appName: appName, isHandoff: isHandoff)
    }

    // MARK: - 测试入口

    /// 供单元测试使用的 TencentAttributeStringType 解析入口
    static func readTencentTextForTesting(from pb: NSPasteboard) -> String? {
        shared.readTencentText(from: pb)
    }

    static func extractOrderedSegmentsForTesting(from html: String, sourceURL: URL?) -> [ContentSegment] {
        shared.extractOrderedSegments(from: html, sourceURL: sourceURL)
    }

    static func readFileURLsForTesting(from pb: NSPasteboard) -> ClipboardItem? {
        shared.readFileURLs(from: pb, appName: "TestApp")
    }

    static func readImageDataForTesting(from pb: NSPasteboard) -> (NSImage, Data)? {
        shared.readImageData(from: pb)
    }

    static func readTextForTesting(from pb: NSPasteboard) -> ClipboardItem? {
        shared.readText(from: pb, appName: "TestApp")
    }

    static func readHTMLForTesting(from pb: NSPasteboard) -> ClipboardItem? {
        shared.readHTML(from: pb, appName: "TestApp")
    }

    static func readRTFForTesting(from pb: NSPasteboard) -> ClipboardItem? {
        shared.readRTF(from: pb, appName: "TestApp")
    }
}
