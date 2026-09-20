import Foundation

/// 用文件书签在原路径失效后继续定位被移动的文件。
enum FileLocationResolver {
    static func makeBookmarks(for paths: [String]) -> [Data?]? {
        let bookmarks = paths.map { path in
            try? URL(fileURLWithPath: path).bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        return bookmarks.contains(where: { $0 != nil }) ? bookmarks : nil
    }

    static func originalURLs(for item: ClipboardItem) -> [URL] {
        item.content
            .split(whereSeparator: \.isNewline)
            .map { URL(fileURLWithPath: String($0)) }
    }

    static func resolvedURLs(for item: ClipboardItem) -> [URL] {
        let originals = originalURLs(for: item)
        guard let bookmarks = item.fileBookmarks else { return originals }

        return originals.enumerated().map { index, original in
            guard !FileManager.default.fileExists(atPath: original.path),
                  bookmarks.indices.contains(index),
                  let bookmark = bookmarks[index]
            else { return original }

            var isStale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return original }
            return resolved.standardizedFileURL
        }
    }

    static func existingURLs(for item: ClipboardItem) -> [URL] {
        resolvedURLs(for: item).filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
