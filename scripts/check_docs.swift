import Foundation

// 只检查仓库使用的 Markdown 内联文件链接；不联网、不写文件、不验证网页和标题锚点。
enum DocumentationCheck {
    enum Target: Equatable {
        case external
        case local(String)
        case invalid(String)
    }

    // macOS 的目录枚举可能返回 /private/tmp，而链接解析返回 /tmp。
    // 缺失目标也从最近的已存在父目录解析，保证比较使用同一种路径表示。
    static func canonicalURL(_ url: URL) -> URL {
        var ancestor = url.standardizedFileURL
        var suffix: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            suffix.insert(ancestor.lastPathComponent, at: 0)
            ancestor.deleteLastPathComponent()
        }
        return suffix.reduce(ancestor.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }
    }

    static func destinations(in markdown: String) throws -> [String] {
        var fence: Character?
        var fenceLength = 0
        var visible: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, first == "`" || first == "~" {
                let count = trimmed.prefix(while: { $0 == first }).count
                if count >= 3 {
                    if fence == nil {
                        fence = first
                        fenceLength = count
                    } else if fence == first, count >= fenceLength,
                              trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty {
                        fence = nil
                    }
                    continue
                }
            }
            if fence == nil { visible.append(line) }
        }
        let text = visible.joined(separator: "\n")
        let regex = try NSRegularExpression(
            pattern: #"!?\[[^\]\n]*\]\(\s*(?:<([^>\n]+)>|([^\s)]+))(?:\s+"[^"\n]*")?\s*\)"#
        )
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            let selected = match.range(at: 1).location == NSNotFound ? 2 : 1
            guard let range = Range(match.range(at: selected), in: text) else { return nil }
            return String(text[range])
        }
    }

    static func target(_ destination: String, document: URL, root: URL) -> Target {
        if destination.hasPrefix("#") { return .local(canonicalURL(document).path) }
        if destination.hasPrefix("//") { return .external }
        if let scheme = URLComponents(string: destination)?.scheme?.lowercased() {
            return ["http", "https", "mailto"].contains(scheme)
                ? .external : .invalid("不允许的链接协议：\(scheme)")
        }
        let raw = String(destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        guard let relative = raw.removingPercentEncoding, !relative.isEmpty else {
            return .invalid("路径为空或百分号编码无效")
        }
        guard !relative.hasPrefix("/"), !relative.hasPrefix("~") else {
            return .invalid("本机绝对路径不能作为项目知识依赖")
        }
        let resolved = canonicalURL(document.deletingLastPathComponent().appendingPathComponent(relative))
        let canonicalRoot = canonicalURL(root).path
        guard resolved.path == canonicalRoot || resolved.path.hasPrefix(canonicalRoot + "/") else {
            return .invalid("链接越出当前仓库")
        }
        guard !relative.split(separator: "/").contains(".codex"), !resolved.pathComponents.contains(".codex") else {
            return .invalid("项目文档不能依赖 .codex 目录")
        }
        return .local(resolved.path)
    }

    static func selfTest() throws {
        let root = URL(fileURLWithPath: "/documentation-check-fixture", isDirectory: true)
        let doc = root.appendingPathComponent("docs/README.md")
        let fixture = "[正文](guide.md) ![图片](<a b.png>)\n~~~md\n[示例](missing.md)\n~~~\n[网页](https://example.com)"
        guard try destinations(in: fixture) == ["guide.md", "a b.png", "https://example.com"],
              try destinations(in: "````md\n```\n[x](ignored.md)\n````\n[x](ok.md)") == ["ok.md"],
              try destinations(in: "[x](guide.md \"标题\")") == ["guide.md"],
              target("../README.md#入口", document: doc, root: root) == .local(root.appendingPathComponent("README.md").path),
              target("a%20b.md", document: doc, root: root) == .local(root.appendingPathComponent("docs/a b.md").path),
              target("https://example.com", document: doc, root: root) == .external,
              target("#入口", document: doc, root: root) == .local(doc.path)
        else { throw NSError(domain: "文档校验自测失败", code: 1) }
        for unsafe in ["../../outside.md", "/tmp/local.md", "~/local.md", "file:///tmp/a.md", "../.codex/map.md", "%ZZ", "%2Ftmp/a.md"] {
            guard case .invalid = target(unsafe, document: doc, root: root) else {
                throw NSError(domain: "未拒绝不安全链接：\(unsafe)", code: 1)
            }
        }
        #if os(macOS)
        let temporaryRoot = canonicalURL(URL(fileURLWithPath: "/tmp"))
        let missing = ".pastry-documentation-self-test/missing.md"
        guard canonicalURL(URL(fileURLWithPath: "/private/tmp/" + missing)).path
                == canonicalURL(URL(fileURLWithPath: "/tmp/" + missing)).path,
              target(missing, document: URL(fileURLWithPath: "/private/tmp/README.md"), root: temporaryRoot)
                == .local(temporaryRoot.appendingPathComponent(missing).path)
        else { throw NSError(domain: "临时目录别名归一化失败", code: 1) }
        #endif
    }

    static func check(root: URL) throws -> [String] {
        let root = canonicalURL(root)
        let fm = FileManager.default
        let docsURL = root.appendingPathComponent("docs", isDirectory: true)
        var enumerationErrors: [String] = []
        guard let enumerator = fm.enumerator(at: docsURL, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles], errorHandler: { url, error in
                enumerationErrors.append("无法读取 \(url.lastPathComponent)：\(error.localizedDescription)")
                return false
            }) else { throw NSError(domain: "无法读取 docs 目录", code: 1) }
        var files = [root.appendingPathComponent("README.md"), root.appendingPathComponent("AGENTS.md")]
        for case let url as URL in enumerator where url.pathExtension == "md" {
            files.append(canonicalURL(url))
        }
        var errors = enumerationErrors
        var links: [String: Set<String>] = [:]
        for file in files.sorted(by: { $0.path < $1.path }) {
            guard canonicalURL(file).path.hasPrefix(root.path + "/") else {
                errors.append("文档文件越出仓库：\(file.lastPathComponent)")
                continue
            }
            let content = try String(contentsOf: file, encoding: .utf8)
            for destination in try destinations(in: content) {
                switch target(destination, document: file, root: root) {
                case .external: break
                case .invalid(let reason): errors.append("\(file.lastPathComponent)：\(destination)（\(reason)）")
                case .local(let path):
                    links[file.path, default: []].insert(path)
                    if !fm.fileExists(atPath: path) {
                        errors.append("\(file.lastPathComponent)：链接目标不存在：\(destination)")
                    }
                }
            }
        }
        for directory in ["architecture", "adr"] {
            let folder = docsURL.appendingPathComponent(directory)
            let index = folder.appendingPathComponent("README.md")
            _ = try String(contentsOf: index, encoding: .utf8) // 缺失索引必须报错
            for file in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                where file.pathExtension == "md" && file.lastPathComponent != "README.md" {
                if !(links[index.path] ?? []).contains(canonicalURL(file).path) {
                    errors.append("docs/\(directory)/README.md 未索引 \(file.lastPathComponent)")
                }
            }
            if !(links[root.appendingPathComponent("README.md").path] ?? []).contains(index.path) {
                errors.append("README.md 缺少 docs/\(directory)/README.md 入口")
            }
        }
        let architecture = docsURL.appendingPathComponent("architecture/README.md").path
        if !(links[root.appendingPathComponent("AGENTS.md").path] ?? []).contains(architecture) {
            errors.append("AGENTS.md 缺少架构索引入口")
        }
        return errors
    }
}

do {
    try DocumentationCheck.selfTest()
    let root = DocumentationCheck.canonicalURL(URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent())
    let errors = try DocumentationCheck.check(root: root)
    if !errors.isEmpty {
        FileHandle.standardError.write(Data((errors.joined(separator: "\n") + "\n").utf8))
        exit(1)
    }
    print("文档校验通过：本地内联链接、仓库边界、架构/ADR 索引与读取入口；自测通过")
} catch {
    FileHandle.standardError.write(Data(("文档校验失败：\(error)\n").utf8))
    exit(1)
}
