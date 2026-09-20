import AppKit
import Foundation
import UniformTypeIdentifiers

enum DragPayloadBuilder {
    struct SelectionPayload: Equatable {
        let text: String
        let webURLs: [URL]
        let fileURLs: [URL]

        var isEmpty: Bool {
            text.isEmpty && webURLs.isEmpty && fileURLs.isEmpty
        }
    }

    static func provider(
        for item: ClipboardItem,
        loadFullContent: (ClipboardItem) -> String? = { _ in nil }
    ) -> NSItemProvider {
        if let provider = urlProvider(for: item, loadFullContent: loadFullContent) {
            return provider
        }

        switch item.sourceFormat {
        case .image:
            let movedImagePath = item.fileBookmarks == nil
                ? nil
                : FileLocationResolver.existingURLs(for: item).first?.path
            let imagePath = movedImagePath
                ?? ImageCacheManager.shared.originalPath(forThumbnail: item.content)
                ?? item.content
            let imageURL = URL(fileURLWithPath: imagePath)
            if FileManager.default.fileExists(atPath: imagePath),
               let provider = NSItemProvider(contentsOf: imageURL) {
                provider.suggestedName = ImageCacheManager.shared.suggestedFilename(forImagePath: imagePath)
                return provider
            }
            return NSItemProvider(object: item.content as NSString)
        case .fileURL:
            if let fileURL = FileLocationResolver.existingURLs(for: item).first,
               let provider = NSItemProvider(contentsOf: fileURL) {
                provider.suggestedName = fileURL.lastPathComponent
                return provider
            }
            return NSItemProvider(object: item.content as NSString)
        default:
            let content = loadFullContent(item) ?? item.content
            return NSItemProvider(object: content as NSString)
        }
    }

    static func providerForSelection(
        _ items: [ClipboardItem],
        loadFullContent: (ClipboardItem) -> String? = { _ in nil }
    ) -> NSItemProvider {
        let text = multiSelectText(items, loadFullContent: loadFullContent)
        guard !text.isEmpty else { return NSItemProvider(object: "" as NSString) }
        return NSItemProvider(object: text as NSString)
    }

    static func payloadForSelection(
        _ items: [ClipboardItem],
        loadFullContent: (ClipboardItem) -> String? = { _ in nil }
    ) -> SelectionPayload {
        SelectionPayload(
            text: multiSelectText(items, loadFullContent: loadFullContent),
            webURLs: webURLsForLinkSelection(items, loadFullContent: loadFullContent),
            fileURLs: fileURLsForSelection(items)
        )
    }

    static func webURLsForLinkSelection(
        _ items: [ClipboardItem],
        loadFullContent: (ClipboardItem) -> String? = { _ in nil }
    ) -> [URL] {
        guard !items.isEmpty else { return [] }
        var urls: [URL] = []
        for item in items {
            let itemURLs = webURLs(in: item, loadFullContent: loadFullContent)
            guard !itemURLs.isEmpty else { return [] }
            urls.append(contentsOf: itemURLs)
        }
        return urls
    }

    static func multiSelectText(
        _ items: [ClipboardItem],
        loadFullContent: (ClipboardItem) -> String? = { _ in nil }
    ) -> String {
        items.compactMap { item -> String? in
            switch item.sourceFormat {
            case .text, .rtf, .html:
                return loadFullContent(item) ?? item.content
            case .fileURL:
                return item.content
            default:
                return nil
            }
        }.joined(separator: "\n")
    }

    static func fileURLsForSelection(_ items: [ClipboardItem]) -> [URL] {
        items.flatMap { item -> [URL] in
            switch item.sourceFormat {
            case .fileURL:
                return FileLocationResolver.existingURLs(for: item)
            case .image:
                if item.fileBookmarks != nil,
                   let movedURL = FileLocationResolver.existingURLs(for: item).first {
                    return [movedURL]
                }
                let path = ImageCacheManager.shared.originalPath(forThumbnail: item.content) ?? item.content
                guard FileManager.default.fileExists(atPath: path) else { return [] }
                return [URL(fileURLWithPath: path)]
            default:
                return []
            }
        }
    }

    static func webURLs(
        in item: ClipboardItem,
        loadFullContent: (ClipboardItem) -> String? = { _ in nil }
    ) -> [URL] {
        guard item.tags.isURL else { return [] }
        let content = loadFullContent(item) ?? item.content
        let lineURLs = content
            .split(whereSeparator: \.isNewline)
            .compactMap { webURL(from: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
        if !lineURLs.isEmpty { return lineURLs }

        guard let detector = Self.linkDetector else { return [] }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return detector.matches(in: content, options: [], range: range).compactMap { match in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return nil }
            return upgradeToHTTPS(url)
        }
    }

    private static func urlProvider(
        for item: ClipboardItem,
        loadFullContent: (ClipboardItem) -> String?
    ) -> NSItemProvider? {
        let urls = webURLs(in: item, loadFullContent: loadFullContent)
        guard !urls.isEmpty else { return nil }
        return urlProvider(for: urls)
    }

    private static func urlProvider(for urls: [URL]) -> NSItemProvider {
        let text = urls.map(\.absoluteString).joined(separator: "\n")
        let provider = urls.count == 1
            ? NSItemProvider(object: urls[0] as NSURL)
            : NSItemProvider(object: text as NSString)
        registerPlainText(text, on: provider)
        registerPrimaryURL(urls[0], on: provider)
        return provider
    }

    private static func registerPlainText(_ text: String, on provider: NSItemProvider) {
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(text.data(using: .utf8), nil)
            return nil
        }
    }

    private static func registerPrimaryURL(_ url: URL, on provider: NSItemProvider) {
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.url.identifier,
            visibility: .all
        ) { completion in
            completion(url.absoluteString.data(using: .utf8), nil)
            return nil
        }
    }

    private static let linkDetector: NSDataDetector? = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func webURL(from text: String) -> URL? {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return upgradeToHTTPS(url)
    }

    private static func upgradeToHTTPS(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url ?? url
    }
}
