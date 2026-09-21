import Foundation
import OSLog

enum DiagnosticLogLevel: String, Codable {
    case debug
    case info
    case notice
    case warning
    case error
    case critical
}

enum DiagnosticsContext: String, Codable {
    case normal
    case development
    case releaseSmoke = "release_smoke"
}

/// Pastry 统一运行日志 interface。
///
/// 所有事件始终进入 Apple Unified Logging；开启“开发诊断记录”后，额外写入本地
/// `runtime.jsonl`。调用方只能传入运维状态和非敏感元数据，禁止传剪贴板正文、
/// 搜索词、完整 URL 或其他用户内容。
struct PastryLogger {
    private let systemLogger: Logger
    let category: String

    init(category: String) {
        self.category = category
        systemLogger = Logger(subsystem: "com.nekutai.pastry", category: category)
    }

    func debug(
        _ message: String,
        event: String,
        metadata: [String: String] = [:],
        durationMilliseconds: Int? = nil
    ) {
        write(.debug, message, event, metadata, durationMilliseconds)
    }

    func info(
        _ message: String,
        event: String,
        metadata: [String: String] = [:],
        durationMilliseconds: Int? = nil
    ) {
        write(.info, message, event, metadata, durationMilliseconds)
    }

    func notice(
        _ message: String,
        event: String,
        metadata: [String: String] = [:],
        durationMilliseconds: Int? = nil
    ) {
        write(.notice, message, event, metadata, durationMilliseconds)
    }

    func warning(
        _ message: String,
        event: String,
        metadata: [String: String] = [:],
        durationMilliseconds: Int? = nil
    ) {
        write(.warning, message, event, metadata, durationMilliseconds)
    }

    func error(
        _ message: String,
        event: String,
        metadata: [String: String] = [:],
        durationMilliseconds: Int? = nil
    ) {
        write(.error, message, event, metadata, durationMilliseconds)
    }

    func critical(
        _ message: String,
        event: String,
        metadata: [String: String] = [:],
        durationMilliseconds: Int? = nil
    ) {
        write(.critical, message, event, metadata, durationMilliseconds)
    }

    private func write(
        _ level: DiagnosticLogLevel,
        _ message: String,
        _ event: String,
        _ metadata: [String: String],
        _ durationMilliseconds: Int?
    ) {
        let safeMetadata = DeveloperDiagnostics.sanitizedMetadata(metadata)
        let metadataText = safeMetadata
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
        let durationText = durationMilliseconds.map { " duration_ms=\($0)" } ?? ""
        let suffix = metadataText.isEmpty ? durationText : "\(durationText) \(metadataText)"
        let renderedMessage = "[\(event)] \(message)\(suffix)"

        switch level {
        case .debug:
            systemLogger.debug("\(renderedMessage, privacy: .public)")
        case .info:
            systemLogger.info("\(renderedMessage, privacy: .public)")
        case .notice:
            systemLogger.notice("\(renderedMessage, privacy: .public)")
        case .warning:
            systemLogger.warning("\(renderedMessage, privacy: .public)")
        case .error:
            systemLogger.error("\(renderedMessage, privacy: .public)")
        case .critical:
            systemLogger.critical("\(renderedMessage, privacy: .public)")
        }

        DeveloperDiagnostics.writeRuntimeEvent(
            level: level,
            category: category,
            event: event,
            message: message,
            metadata: safeMetadata,
            durationMilliseconds: durationMilliseconds
        )
    }
}

/// 开发诊断：结构化运行日志 + 本地性能计时 + 功能使用计数，共用同一开关，不上报。
enum DeveloperDiagnostics {
    private static let log = Logger(subsystem: "com.nekutai.pastry", category: "diagnostics")
    private static let queue = DispatchQueue(label: "com.nekutai.pastry.diagnostics", qos: .utility)
    private static let usageFileName = "usage.json"
    private static let perfFileName = "perf.log"
    private static let runtimeFileName = "runtime.jsonl"
    private static let runtimeRotatedFilePrefix = "runtime"
    private static let runtimeLogDefaultMaxBytes: UInt64 = 5 * 1024 * 1024
    private static let runtimeLogGenerationCount = 3
    private static let usageVersion = 2
    private static let sessionID = UUID().uuidString.lowercased()
    private static let sensitiveMetadataKeys: Set<String> = [
        "clipboard", "content", "html", "pasteboard", "query", "rtf", "text", "url"
    ]

    /// 设置开关或环境变量开启时为 true。
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.performanceLoggingEnabled)
            || ProcessInfo.processInfo.environment["PASTRY_DIAGNOSTICS"] == "1"
            || ProcessInfo.processInfo.environment["PASTRY_PERF_LOG"] == "1"
    }

    static var shouldPresentLaunchWindows: Bool {
        currentContext != .releaseSmoke
    }

    /// 功能使用计数 +1（开关关闭时 no-op）。
    static func record(_ event: String) {
        guard isEnabled, !event.isEmpty else { return }
        let context = currentContext
        let now = currentDate
        queue.async {
            incrementUsage(event, context: context, at: now)
        }
    }

    /// 写入一行性能日志（格式保持与 scripts/bench.sh 兼容）。
    static func writePerfLine(_ line: String) {
        guard isEnabled else { return }
        let context = currentContext
        queue.async {
            let logDir = logsDirectoryOverrideForTesting ?? AppDirectories.logsDirectory()
            guard AppDirectories.ensureDirectory(logDir, logCategory: "diagnostics") else { return }
            let logFile = logDir.appendingPathComponent(perfFileName)
            let renderedLine = "\(line) | context: \(context.rawValue)\n"
            if let handle = try? FileHandle(forWritingTo: logFile) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(Data(renderedLine.utf8))
            } else {
                try? renderedLine.write(to: logFile, atomically: true, encoding: .utf8)
            }
        }
    }

    /// 写入结构化运行事件。文件仅在开发诊断开启时产生。
    static func writeRuntimeEvent(
        level: DiagnosticLogLevel,
        category: String,
        event: String,
        message: String,
        metadata: [String: String] = [:],
        durationMilliseconds: Int? = nil
    ) {
        guard isEnabled, !category.isEmpty, !event.isEmpty else { return }
        let context = currentContext
        queue.async {
            let record = RuntimeLogRecord(
                timestamp: isoNow(),
                sessionID: sessionID,
                context: context,
                level: level,
                category: category,
                event: event,
                message: message,
                metadata: sanitizedMetadata(metadata),
                durationMilliseconds: durationMilliseconds,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? AppVersion.current,
                build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                    ?? AppVersion.build
            )

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                var data = try encoder.encode(record)
                data.append(0x0A)
                try appendRuntimeData(data)
            } catch {
                log.error("写入 runtime.jsonl 失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Testing helpers

    /// 同步读取当前计数（测试用；会等待队列排空）。
    static func snapshotCountsForTesting() -> [String: Int] {
        queue.sync {
            loadUsageFile().counts
        }
    }

    /// 重置 usage.json（测试用）。
    static func resetUsageForTesting() {
        queue.sync {
            let url = usageFileURL()
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 等待已排队的文件日志写入完成。仅在进程即将退出时调用。
    static func flush() {
        queue.sync {}
    }

    static func flushForTesting() {
        flush()
    }

    static func resetRuntimeLogForTesting() {
        queue.sync {
            for url in runtimeLogURLs() {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// 指定测试目录覆盖（测试用）；传 nil 恢复默认。
    nonisolated(unsafe) static var logsDirectoryOverrideForTesting: URL?
    nonisolated(unsafe) static var runtimeLogMaxBytesOverrideForTesting: UInt64?
    nonisolated(unsafe) static var contextOverrideForTesting: DiagnosticsContext?
    nonisolated(unsafe) static var dateOverrideForTesting: Date?
    // MARK: - Private

    private struct UsageFile: Codable {
        var version: Int
        var startedAt: String
        var dailyCountsStartedAt: String
        var updatedAt: String
        var counts: [String: Int]
        var contextCounts: [String: [String: Int]]
        var dailyCounts: [String: [String: [String: Int]]]

        enum CodingKeys: String, CodingKey {
            case version
            case startedAt
            case dailyCountsStartedAt
            case updatedAt
            case counts
            case contextCounts
            case dailyCounts
        }

        init(
            version: Int,
            startedAt: String,
            dailyCountsStartedAt: String,
            updatedAt: String,
            counts: [String: Int] = [:],
            contextCounts: [String: [String: Int]] = [:],
            dailyCounts: [String: [String: [String: Int]]] = [:]
        ) {
            self.version = version
            self.startedAt = startedAt
            self.dailyCountsStartedAt = dailyCountsStartedAt
            self.updatedAt = updatedAt
            self.counts = counts
            self.contextCounts = contextCounts
            self.dailyCounts = dailyCounts
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? isoNow()
            startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt) ?? updatedAt
            dailyCountsStartedAt = try container.decodeIfPresent(
                String.self,
                forKey: .dailyCountsStartedAt
            ) ?? updatedAt
            counts = try container.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
            contextCounts = try container.decodeIfPresent(
                [String: [String: Int]].self,
                forKey: .contextCounts
            ) ?? [:]
            dailyCounts = try container.decodeIfPresent(
                [String: [String: [String: Int]]].self,
                forKey: .dailyCounts
            ) ?? [:]
        }
    }

    private struct RuntimeLogRecord: Codable {
        let timestamp: String
        let sessionID: String
        let context: DiagnosticsContext
        let level: DiagnosticLogLevel
        let category: String
        let event: String
        let message: String
        let metadata: [String: String]
        let durationMilliseconds: Int?
        let appVersion: String
        let build: String

        enum CodingKeys: String, CodingKey {
            case timestamp
            case sessionID = "session_id"
            case context
            case level
            case category
            case event
            case message
            case metadata
            case durationMilliseconds = "duration_ms"
            case appVersion = "app_version"
            case build
        }
    }

    private static func usageFileURL() -> URL {
        let dir = logsDirectoryOverrideForTesting ?? AppDirectories.logsDirectory()
        return dir.appendingPathComponent(usageFileName)
    }

    private static func loadUsageFile(at now: Date = currentDate) -> UsageFile {
        let url = usageFileURL()
        let timestamp = isoNow(now)
        guard let data = try? Data(contentsOf: url),
              var decoded = try? JSONDecoder().decode(UsageFile.self, from: data)
        else {
            return UsageFile(
                version: usageVersion,
                startedAt: timestamp,
                dailyCountsStartedAt: timestamp,
                updatedAt: timestamp
            )
        }
        if decoded.version < usageVersion {
            decoded.version = usageVersion
            decoded.startedAt = earliestRuntimeTimestamp() ?? decoded.startedAt
            decoded.dailyCountsStartedAt = timestamp
        }
        return decoded
    }

    private static func incrementUsage(_ event: String, context: DiagnosticsContext, at now: Date) {
        let dir = logsDirectoryOverrideForTesting ?? AppDirectories.logsDirectory()
        guard AppDirectories.ensureDirectory(dir, logCategory: "diagnostics") else { return }

        var file = loadUsageFile(at: now)
        let timestamp = isoNow(now)
        let day = String(timestamp.prefix(10))
        file.counts[event, default: 0] += 1
        file.contextCounts[context.rawValue, default: [:]][event, default: 0] += 1
        file.dailyCounts[day, default: [:]][context.rawValue, default: [:]][event, default: 0] += 1
        file.version = usageVersion
        file.updatedAt = timestamp

        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: usageFileURL(), options: .atomic)
        } catch {
            log.error("写入 usage.json 失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func appendRuntimeData(_ data: Data) throws {
        let dir = logsDirectoryOverrideForTesting ?? AppDirectories.logsDirectory()
        guard AppDirectories.ensureDirectory(dir, logCategory: "diagnostics") else { return }
        let url = dir.appendingPathComponent(runtimeFileName)
        try rotateRuntimeLogIfNeeded(url: url, addingBytes: UInt64(data.count))

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    private static func rotateRuntimeLogIfNeeded(url: URL, addingBytes: UInt64) throws {
        let currentBytes = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?
            .uint64Value ?? 0
        let maxBytes = runtimeLogMaxBytesOverrideForTesting ?? runtimeLogDefaultMaxBytes
        guard currentBytes > 0, currentBytes + addingBytes > maxBytes else { return }

        let dir = url.deletingLastPathComponent()
        let oldest = dir.appendingPathComponent("\(runtimeRotatedFilePrefix).\(runtimeLogGenerationCount).jsonl")
        try? FileManager.default.removeItem(at: oldest)

        if runtimeLogGenerationCount > 1 {
            for generation in stride(from: runtimeLogGenerationCount - 1, through: 1, by: -1) {
                let source = dir.appendingPathComponent("\(runtimeRotatedFilePrefix).\(generation).jsonl")
                let destination = dir.appendingPathComponent("\(runtimeRotatedFilePrefix).\(generation + 1).jsonl")
                if FileManager.default.fileExists(atPath: source.path) {
                    try? FileManager.default.moveItem(at: source, to: destination)
                }
            }
        }

        let firstRotation = dir.appendingPathComponent("\(runtimeRotatedFilePrefix).1.jsonl")
        try? FileManager.default.removeItem(at: firstRotation)
        try FileManager.default.moveItem(at: url, to: firstRotation)
    }

    private static func runtimeLogURLs() -> [URL] {
        let dir = logsDirectoryOverrideForTesting ?? AppDirectories.logsDirectory()
        return [dir.appendingPathComponent(runtimeFileName)] + (1...runtimeLogGenerationCount).map {
            dir.appendingPathComponent("\(runtimeRotatedFilePrefix).\($0).jsonl")
        }
    }

    fileprivate static func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { result, pair in
            let normalizedKey = pair.key.lowercased()
            let keyParts = normalizedKey.split { !$0.isLetter && !$0.isNumber }.map(String.init)
            let describesAggregate = ["count", "length", "size", "type"].contains(keyParts.last)
            let isSensitive = !describesAggregate && keyParts.contains { sensitiveMetadataKeys.contains($0) }
            result[pair.key] = isSensitive ? "<redacted>" : sanitizedMetadataValue(pair.value)
        }
    }

    private static func sanitizedMetadataValue(_ value: String) -> String {
        let normalized = value.lowercased()
        if normalized.contains("://") || normalized.contains("www.") {
            return "<redacted>"
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard !home.isEmpty else { return value }
        return value.replacingOccurrences(of: home, with: "~")
    }

    private static var currentContext: DiagnosticsContext {
        if let contextOverrideForTesting {
            return contextOverrideForTesting
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "--diagnostics-context"),
           arguments.indices.contains(flagIndex + 1),
           let context = DiagnosticsContext(rawValue: arguments[flagIndex + 1]) {
            return context
        }
        if let rawValue = ProcessInfo.processInfo.environment["PASTRY_DIAGNOSTICS_CONTEXT"],
           let context = DiagnosticsContext(rawValue: rawValue) {
            return context
        }
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        if bundleIdentifier.hasSuffix(".dev") || version.contains("-dev") {
            return .development
        }
        return .normal
    }

    private static var currentDate: Date {
        dateOverrideForTesting ?? Date()
    }

    private static func earliestRuntimeTimestamp() -> String? {
        for url in runtimeLogURLs().reversed() where FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 8 * 1024),
                  let line = String(data: data, encoding: .utf8)?.split(separator: "\n").first,
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let timestamp = object["timestamp"] as? String
            else { continue }
            return timestamp
        }
        return nil
    }

    private static func isoNow(_ date: Date = currentDate) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

/// 稳定事件名，避免散落字符串拼写不一致。
enum DiagnosticsEvent {
    static let overlayOpen = "overlay.open"
    static let overlayDismiss = "overlay.dismiss"

    static let pasteSingle = "paste.single"
    static let pasteMulti = "paste.multi"
    static let pasteCmdNumber = "paste.cmd_number"
    static let cardClickPaste = "card_click.paste"

    static let copy = "copy"
    static let preview = "preview"
    static let share = "share"
    static let open = "open"
    static let showInFinder = "show_in_finder"
    static let smartActionOpen = "smart_action.open"

    static let favoritePin = "favorite.pin"
    static let favoriteUnpin = "favorite.unpin"

    static let delete = "delete"
    static let deleteIncludingFavorite = "delete.including_favorite"
    static let clearAll = "clear_all"

    static let searchOpen = "search.open"
    static let searchQuery = "search.query"

    static let dragSingle = "drag.single"
    static let dragMulti = "drag.multi"

    static let tabAll = "tab.all"
    static let tabFavorites = "tab.favorites"

    static let filterClear = "filter.clear"
    static let filterApp = "filter.app"
    static let filterURL = "filter.url"
    static let filterHandoff = "filter.handoff"

    static func filterNote(_ filter: StoreManager.NoteFilter) -> String {
        "filter.note.\(filter.rawValue)"
    }

    static let accessibilityDenied = "accessibility.denied"

    static func filterType(_ format: SourceFormat) -> String {
        "filter.type.\(format.rawValue)"
    }

    static func filterTime(_ filter: StoreManager.TimeFilter) -> String {
        switch filter {
        case .any: return "filter.time.any"
        case .today: return "filter.time.today"
        case .yesterday: return "filter.time.yesterday"
        case .thisWeek: return "filter.time.thisWeek"
        case .lastWeek: return "filter.time.lastWeek"
        case .last30Days: return "filter.time.last30Days"
        }
    }
}
