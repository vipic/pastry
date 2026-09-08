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

        log.error("无法获取 Application Support 目录，停止初始化以避免把用户数据写入临时目录")
        preconditionFailure("Application Support directory unavailable")
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
