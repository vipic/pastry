import Cocoa

// MARK: - 来源格式（纯来源，不可变）
enum SourceFormat: String, Codable, CaseIterable {
    case text
    case rtf
    case html
    case image
    case fileURL

    var iconName: String {
        switch self {
        case .text:    return "text.alignleft"
        case .rtf:     return "doc.richtext"
        case .html:    return "chevron.left.forwardslash.chevron.right"
        case .image:   return "photo"
        case .fileURL: return "folder"
        }
    }

    var label: String {
        switch self {
        case .text:    return L10n["filter.type.text"]
        case .rtf:     return L10n["filter.type.rtf"]
        case .html:    return L10n["filter.type.html"]
        case .image:   return L10n["filter.type.image"]
        case .fileURL: return L10n["filter.type.fileURL"]
        }
    }

    /// 数据库存储键
    var storageKey: String { rawValue }

    init(storageKey: String) {
        switch storageKey {
        case "rtf":     self = .rtf
        case "html":    self = .html
        case "image":   self = .image
        case "fileURL": self = .fileURL
        case "url":     self = .text  // 存量 .url → .text
        default:        self = .text
        }
    }
}

// MARK: - 语义标记
struct ContentTags: Codable, Equatable {
    var isURL: Bool = false
    var hasSegments: Bool = false
    var isMultiFile: Bool = false
    var isMissing: Bool = false

    static let empty = ContentTags()
}

// MARK: - HTML 内容段（保留原始 DOM 图文顺序）
enum ContentSegment: Codable, Equatable {
    case text(String)
    case image(url: String)

    var textValue: String? { if case .text(let s) = self { return s }; return nil }
    var imageURL: String? { if case .image(let u) = self { return u }; return nil }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let t = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(t)
        } else if let u = try container.decodeIfPresent(String.self, forKey: .image) {
            self = .image(url: u)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "invalid segment"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s):  try container.encode(s, forKey: .text)
        case .image(let u): try container.encode(u, forKey: .image)
        }
    }

    private enum CodingKeys: String, CodingKey { case text, image }
}

// MARK: - 核心数据模型
struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let content: String         // 文本内容 / 图片缓存路径 / 文件URL拼接
    let sourceFormat: SourceFormat
    let tags: ContentTags
    var appName: String?        // 来源应用名；剪贴板数据读取后可更新前台应用归属
    let isHandoff: Bool          // 是否来自 Handoff（iPhone/iPad 通用剪贴板）
    let textAnnotation: String?       // 图片附带的文字（同时复制图文时保留）
    var linkTitle: String?            // 链接预览抓取的页面标题（og:title / <title>）（可变，不计入 hash）
    let segmentsJSON: String?         // segments 的原始 JSON（延迟解码）
    let rawFormatData: Data?          // 原始格式数据（RTF/HTML 的原始字节，粘贴时写回）
    let rawFormatType: String?        // 原始格式的剪贴板类型（public.rtf / public.html）
    let fileBookmarks: [Data?]?     // 文件原路径失效后用于跟随 Finder 移动
    var displayCount: Int             // 被粘贴回的次数（可变，不计入 hash）
    var isPinned: Bool                // 收藏（favorite）；自动清理会跳过，用户删除不豁免
    var favoriteNote: String?         // 场景备注；所有条目均可添加（可变，不计入 hash）
    var favoriteNoteUpdatedAt: Date?  // 场景备注更新时间（可变，不计入 hash）

    /// segments 按需解码（仅 .html 类型使用，大文本不复制时不解码）
    var segments: [ContentSegment]? {
        guard let json = segmentsJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([ContentSegment].self, from: data)
    }

    /// 从 segments 中提取的远程图片 URL 列表（方便卡片视图和去重使用）
    var imageURLs: [String]? {
        segments?.compactMap { $0.imageURL }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        content: String,
        sourceFormat: SourceFormat,
        tags: ContentTags = .empty,
        appName: String? = nil,
        isHandoff: Bool = false,
        textAnnotation: String? = nil,
        linkTitle: String? = nil,
        segments: [ContentSegment]? = nil,
        segmentsJSON: String? = nil,
        rawFormatData: Data? = nil,
        rawFormatType: String? = nil,
        fileBookmarks: [Data?]? = nil,
        displayCount: Int = 0,
        isPinned: Bool = false,
        favoriteNote: String? = nil,
        favoriteNoteUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.sourceFormat = sourceFormat
        self.tags = tags
        self.appName = appName
        self.isHandoff = isHandoff
        self.textAnnotation = textAnnotation
        self.linkTitle = linkTitle
        // 优先用已有 JSON，否则从 segments 编码
        if let json = segmentsJSON {
            self.segmentsJSON = json
        } else if let segs = segments, !segs.isEmpty {
            self.segmentsJSON = (try? JSONEncoder().encode(segs))
                .flatMap { String(data: $0, encoding: .utf8) }
        } else {
            self.segmentsJSON = nil
        }
        self.rawFormatData = rawFormatData
        self.rawFormatType = rawFormatType
        self.displayCount = displayCount
        self.fileBookmarks = fileBookmarks
        self.isPinned = isPinned
        self.favoriteNote = favoriteNote
        self.favoriteNoteUpdatedAt = favoriteNoteUpdatedAt
    }

    /// 去重用的内容摘要（文本类格式统一前缀，文件/图片保留独立类型）
    var dedupKey: String {
        let typePrefix: String = switch sourceFormat {
        case .text, .rtf, .html: "text"
        default: sourceFormat.storageKey
        }
        let segSig = segmentsJSON ?? "nil"
        // 只取前 64 字符避免超长 key
        let segPreview = segSig.count > 64 ? String(segSig.prefix(64)) : segSig
        return "\(typePrefix):\(content):\(textAnnotation ?? ""):\(imageURLs?.joined(separator: ",") ?? ""):\(segPreview)"
    }
}

// MARK: - 搜索过滤
extension Array where Element == ClipboardItem {

    /// 搜索过滤：对 content / linkTitle / favoriteNote 大小写不敏感子串匹配，可选匹配 appName。
    /// 空查询或无内容匹配时返回空数组。
    /// - Parameters:
    ///   - query: 搜索关键词（大小写不敏感）
    ///   - includeAppName: 是否同时搜索来源 App 名称，默认 true
    /// - Returns: 匹配的 ClipboardItem 数组（保持原序）
    func filtered(by query: String, includeAppName: Bool = true) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lowerQuery = trimmed.lowercased()

        return self.filter { item in
            if item.content.lowercased().contains(lowerQuery) {
                return true
            }
            if let title = item.linkTitle, title.lowercased().contains(lowerQuery) {
                return true
            }
            if let note = item.favoriteNote, note.lowercased().contains(lowerQuery) {
                return true
            }
            if includeAppName, let app = item.appName {
                return app.lowercased().contains(lowerQuery)
            }
            return false
        }
    }
}

// MARK: - 历史状态统计
struct ClipboardStats: Codable {
    let totalItems: Int
    let todayItems: Int
    let favoriteCount: Int
    let storageSizeKB: Int
}
