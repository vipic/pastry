import SwiftUI
import Cocoa
import UniformTypeIdentifiers
import Quartz

// MARK: - 链接预览加载器
final class LinkPreviewLoader {
    nonisolated(unsafe) static let shared = LinkPreviewLoader()

    struct Preview {
        let title: String
        let description: String?
        let imageURL: String?
        let host: String
    }

    /// Wrapper to store Preview struct in NSCache (requires class type)
    final class PreviewWrapper {
        let preview: Preview
        init(_ preview: Preview) { self.preview = preview }
    }

    private let cache: NSCache<NSString, PreviewWrapper> = {
        let c = NSCache<NSString, PreviewWrapper>()
        c.countLimit = 200
        return c
    }()

    private static let htmlTagRegexes: [String: NSRegularExpression] = {
        ["meta", "link", "img"].reduce(into: [:]) { dict, name in
            dict[name] = try? NSRegularExpression(
                pattern: "<\(name)\\b[^>]*>",
                options: .caseInsensitive
            )
        }
    }()

    private init() {}

    /// 同步查询缓存（不发起网络请求）
    func cachedPreview(for key: String) -> Preview? {
        cache.object(forKey: key as NSString)?.preview
    }

    func load(url: URL, completion: @escaping (Preview?) -> Void) {
        guard NetworkAccessPolicy.isLinkPreviewEnabled else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let key = url.absoluteString
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached.preview)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        BoundedRemoteResourceLoader.shared.load(
            request: request,
            maxBytes: NetworkAccessPolicy.maxHTMLBytes
        ) { [weak self] data, response, _ in
            guard let self,
                  NetworkAccessPolicy.responseWithinLimit(response, maxBytes: NetworkAccessPolicy.maxHTMLBytes),
                  let data = data,
                  data.count <= NetworkAccessPolicy.maxHTMLBytes,
                  let html = String(data: data, encoding: .utf8)
            else { DispatchQueue.main.async { completion(nil) }; return }
            let title = self.extractMeta(from: html, tag: "og:title")
                ?? self.extractTitleTag(from: html)
                ?? self.extractMeta(from: html, tag: "og:site_name")
            let description = self.extractMeta(from: html, tag: "og:description")
            let imageURL = self.extractPreviewImageMeta(from: html).flatMap { src in
                self.resolveImageURL(src: src, baseURL: url)
            } ?? self.extractLinkImage(from: html, baseURL: url)
                ?? self.extractBestImage(from: html, baseURL: url)
            let preview = Preview(
                title: title ?? "",
                description: description,
                imageURL: imageURL,
                host: url.host ?? ""
            )
            self.cache.setObject(PreviewWrapper(preview), forKey: key as NSString)
            DispatchQueue.main.async { completion(preview) }
        }
    }

    // MARK: - HTML 元数据提取

    private func extractMeta(from html: String, tag: String) -> String? {
        let target = tag.lowercased()
        for metaTag in htmlTags(named: "meta", from: html) {
            let attrs = extractAttributes(from: metaTag)
            guard let content = attrs["content"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty
            else { continue }

            if attrs["property"]?.lowercased() == target || attrs["name"]?.lowercased() == target {
                return content
            }
            if target.hasPrefix("itemprop:"),
               attrs["itemprop"]?.lowercased() == String(target.dropFirst("itemprop:".count)) {
                return content
            }
        }
        return nil
    }

    private func extractPreviewImageMeta(from html: String) -> String? {
        let imageTags = [
            "og:image",
            "og:image:url",
            "og:image:secure_url",
            "twitter:image",
            "twitter:image:src",
            "itemprop:image",
        ]
        for tag in imageTags {
            if let value = extractMeta(from: html, tag: tag) {
                return value
            }
        }
        return nil
    }

    private func extractLinkImage(from html: String, baseURL: URL) -> String? {
        for linkTag in htmlTags(named: "link", from: html) {
            let attrs = extractAttributes(from: linkTag)
            guard let href = cleanedSource(attrs["href"]) else { continue }
            let rel = attrs["rel"]?.lowercased() ?? ""
            let `as` = attrs["as"]?.lowercased() ?? ""
            let type = attrs["type"]?.lowercased() ?? ""

            if rel.contains("image_src") || (rel.contains("preload") && `as` == "image") {
                return resolveImageURL(src: href, baseURL: baseURL)
            }
            if rel.contains("preload") && type.hasPrefix("image/") {
                return resolveImageURL(src: href, baseURL: baseURL)
            }
        }
        return nil
    }

    private func extractTitleTag(from html: String) -> String? {
        guard let s = html.range(of: "<title>", options: .caseInsensitive),
              let e = html.range(of: "</title>", options: .caseInsensitive),
              s.upperBound <= e.lowerBound
        else { return nil }
        let t = html[s.upperBound..<e.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 相对路径图片 URL 用页面 URL 解析；http 图源升级为 https，以通过远程资源策略。
    private func resolveImageURL(src: String, baseURL: URL) -> String? {
        let cleaned = src
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
        guard !cleaned.isEmpty else { return nil }

        guard var resolved = URL(string: cleaned, relativeTo: baseURL)?.absoluteURL else {
            return URL(string: cleaned)?.absoluteString
        }
        if resolved.scheme?.lowercased() == "http",
           var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            if let httpsURL = components.url {
                resolved = httpsURL
            }
        }
        return resolved.absoluteString
    }

    /// og:image 缺失时的降级方案：语义排序选择最佳内容图片
    private func extractBestImage(from html: String, baseURL: URL) -> String? {
        let matches = htmlTags(named: "img", from: html)

        struct Candidate {
            let src: String
            let score: Int
            let order: Int
        }
        var candidates: [Candidate] = []

        for (index, tag) in matches.prefix(30).enumerated() {
            guard let src = extractImageSource(from: tag) else { continue }

            let lower = src.lowercased()
            let lowerTag = tag.lowercased()

            // 只硬过滤明确的追踪/占位图；logo、icon、avatar 参与排序但降权。
            if isHardNoiseImage(src: lower, tag: lowerTag) { continue }

            // 尺寸过滤：跳过明确的小图标
            if isSmallIcon(tag: tag) { continue }

            // 打分
            var score = 0

            // 语义关键词加分
            let semanticBoost = [
                "featured": 20, "hero": 20, "cover": 15, "wp-image": 15,
                "thumbnail": 12, "thumb": 10,
                "og-image": 18, "post-image": 15, "entry-image": 15,
                "article-image": 15, "content-image": 12,
            ]
            for (keyword, points) in semanticBoost {
                if lowerTag.contains(keyword) || lower.contains(keyword) {
                    score += points
                }
            }

            score += noisePenalty(src: lower, tag: lowerTag)

            // 尺寸加分
            score += sizeScore(from: tag)

            // alt 文本非空加分（说明是内容图）
            if let alt = extractAttr(from: tag, attr: "alt"), !alt.trimmingCharacters(in: .whitespaces).isEmpty {
                let lt = alt.lowercased()
                if !lt.contains("logo") && !lt.contains("icon") && !lt.contains("home") {
                    score += 5
                }
            }

            candidates.append(Candidate(src: src, score: score, order: index))
        }

        // 按分数降序，取最佳
        candidates.sort {
            if $0.score == $1.score { return $0.order < $1.order }
            return $0.score > $1.score
        }

        if let best = candidates.first {
            return resolveImageURL(src: best.src, baseURL: baseURL)
        }

        // 全部被过滤：降级取前 30 个中第一个可解析的非 dataURI 图片，仍支持 lazy/srcset。
        for tag in matches.prefix(30) {
            guard let src = extractImageSource(from: tag) else { continue }
            return resolveImageURL(src: src, baseURL: baseURL)
        }

        return nil
    }

    // MARK: - 图片语义分析辅助

    private func htmlTags(named name: String, from html: String) -> [String] {
        guard let regex = Self.htmlTagRegexes[name] else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let tagRange = Range(match.range, in: html) else { return nil }
            return String(html[tagRange])
        }
    }

    private func extractAttributes(from tag: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"([\w:-]+)\s*=\s*(["'])(.*?)\2"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [:] }
        let range = NSRange(tag.startIndex..., in: tag)
        var attrs: [String: String] = [:]
        for match in regex.matches(in: tag, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 3), in: tag)
            else { continue }
            attrs[String(tag[nameRange]).lowercased()] = String(tag[valueRange])
        }
        return attrs
    }

    private func extractImageSource(from tag: String) -> String? {
        let attrs = extractAttributes(from: tag)

        if let src = cleanedSource(attrs["src"]), !src.hasPrefix("data:") {
            return src
        }

        for attr in ["data-src", "data-original", "data-lazy-src", "data-image"] {
            if let src = cleanedSource(attrs[attr]) {
                return src
            }
        }

        for attr in ["srcset", "data-srcset"] {
            if let src = bestSource(fromSrcset: attrs[attr]) {
                return src
            }
        }

        return nil
    }

    private func cleanedSource(_ value: String?) -> String? {
        guard let value else { return nil }
        let src = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return src.isEmpty || src.hasPrefix("data:") ? nil : src
    }

    private func bestSource(fromSrcset srcset: String?) -> String? {
        guard let srcset else { return nil }
        struct SourceSetCandidate {
            let src: String
            let score: Double
            let order: Int
        }
        let candidates = srcset.split(separator: ",").enumerated().compactMap { index, raw -> SourceSetCandidate? in
            let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            guard let first = parts.first else { return nil }
            let src = String(first)
            guard !src.isEmpty, !src.hasPrefix("data:") else { return nil }
            let descriptor = parts.dropFirst().first.map(String.init) ?? ""
            let score: Double
            if descriptor.hasSuffix("w"), let width = Double(descriptor.dropLast()) {
                score = width
            } else if descriptor.hasSuffix("x"), let scale = Double(descriptor.dropLast()) {
                score = scale * 1_000
            } else {
                score = 0
            }
            return SourceSetCandidate(src: src, score: score, order: index)
        }
        return candidates.sorted {
            if $0.score == $1.score { return $0.order < $1.order }
            return $0.score > $1.score
        }.first?.src
    }

    /// 从标签提取指定属性值
    private func extractAttr(from tag: String, attr: String) -> String? {
        extractAttributes(from: tag)[attr.lowercased()]
    }

    /// 是否为明确无内容价值的噪音图片（追踪像素等）
    private func isHardNoiseImage(src: String, tag: String) -> Bool {
        let hardNoisePatterns = [
            "1x1", "pixel", "tracking", "beacon", "analytics",
        ]
        for pattern in hardNoisePatterns {
            if src.contains(pattern) || tag.contains(pattern) { return true }
        }
        return false
    }

    private func noisePenalty(src: String, tag: String) -> Int {
        let penalties = [
            ("favicon", -35),
            ("gravatar", -30),
            ("avatar", -25),
            ("logo", -20),
            ("icon", -18),
            ("button", -12),
            ("header", -10),
            ("footer", -10),
            ("menu", -10),
            ("nav", -10),
            ("social", -10),
        ]
        return penalties.reduce(0) { partial, item in
            let (pattern, penalty) = item
            return src.contains(pattern) || tag.contains(pattern) ? partial + penalty : partial
        }
    }

    /// 是否为明确的小图标（宽高都很小）
    private func isSmallIcon(tag: String) -> Bool {
        let width = extractAttr(from: tag, attr: "width").flatMap(Int.init) ?? 0
        let height = extractAttr(from: tag, attr: "height").flatMap(Int.init) ?? 0
        if width > 0 && height > 0 {
            if width <= 2 || height <= 2 { return true }
            return width < 100 && height < 100
        }
        return false
    }

    /// 根据标签尺寸估算得分
    private func sizeScore(from tag: String) -> Int {
        var w = 0, h = 0
        if let ws = extractAttr(from: tag, attr: "width"), let v = Int(ws) { w = v }
        if let hs = extractAttr(from: tag, attr: "height"), let v = Int(hs) { h = v }
        if w > 0 && h > 0 {
            let area = w * h
            if area >= 500_000 { return 15 }      // ≥ 1000×500
            if area >= 200_000 { return 10 }      // ≥ 500×400
            if area >= 80_000  { return 5 }       // ≥ 400×200
        }
        // 从 URL 参数推测（如 ?w=1200 或 /1200x800）
        if let wRegex = try? NSRegularExpression(pattern: "[?&/]w=(\\d{3,4})", options: .caseInsensitive) {
            let nsTag = tag as NSString
            let range = NSRange(location: 0, length: nsTag.length)
            if let m = wRegex.firstMatch(in: tag, range: range),
               let r = Range(m.range(at: 1), in: tag),
               let v = Int(tag[r]), v >= 800 { return 12 }
        }
        return 0
    }

    // MARK: — 向后兼容

    private func extractTitle(from html: String) -> String? {
        extractTitleTag(from: html) ?? extractMeta(from: html, tag: "og:title")
    }

    // MARK: — 测试入口

    static func extractMetaForTesting(from html: String, tag: String) -> String? {
        shared.extractMeta(from: html, tag: tag)
    }

    static func extractBestImageForTesting(from html: String, baseURL: URL?) -> String? {
        shared.extractBestImage(from: html, baseURL: baseURL ?? URL(string: "https://example.com")!)
    }

    static func resolveImageURLForTesting(src: String, baseURL: URL?) -> String? {
        shared.resolveImageURL(src: src, baseURL: baseURL ?? URL(string: "https://example.com")!)
    }

    static func extractLinkImageForTesting(from html: String, baseURL: URL?) -> String? {
        shared.extractLinkImage(from: html, baseURL: baseURL ?? URL(string: "https://example.com")!)
    }

    static func extractTitleTagForTesting(from html: String) -> String? {
        shared.extractTitleTag(from: html)
    }
}
