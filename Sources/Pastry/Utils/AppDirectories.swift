import Foundation
import OSLog

enum AppDirectories {
    private static let log = Logger(subsystem: "com.nekutai.pastry", category: "app-directories")

    static func applicationSupportDirectory() -> URL {
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return appSupport.appendingPathComponent(Constants.appName)
        }

        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent(Constants.appName)
            .appendingPathComponent("ApplicationSupportFallback")
        // 严重退化：降级到 tmp 意味着数据库 / 图片缓存将在系统重启时被清除。
        // 对应 C8 建议，记一条醒目的 log 以便排查。
        log.error("""
            ⚠️ 无法获取 Application Support 目录，降级到临时目录。\
            数据将在重启后丢失：\(fallback.path, privacy: .public)
            """)
        return fallback
    }

    /// `~/Library/Logs/Pastry`（DEBUG 为 Pastry Dev）
    static func logsDirectory() -> URL {
        if let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            return library
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent(Constants.appName, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(Constants.appName)
            .appendingPathComponent("LogsFallback")
    }

    @discardableResult
    static func ensureDirectory(_ url: URL, logCategory: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            let logger = Logger(subsystem: "com.nekutai.pastry", category: logCategory)
            logger.error("无法创建目录: \(url.path, privacy: .public), error: \(error.localizedDescription)")
            return false
        }
    }
}
