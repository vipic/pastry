import Foundation
import AppKit
import OSLog

// MARK: - 更新检查器
// 对接 GitHub Releases API，提供版本检查与二进制下载
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let log = PastryLogger(category: "update")
    private let session: URLSession
    private let lastCheckKey = "PastryLastUpdateCheck"
    private let checkInterval: TimeInterval = 86_400 // 24 小时
    private static let maxDownloadBytes: Int64 = 300 * 1024 * 1024

    /// 当前 app 是否为开发版本
    var isDevBuild: Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return version.contains("-dev")
    }

    // MARK: - 公开发布信息

    struct ReleaseInfo: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let published_at: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let size: Int
        }
    }

    struct ReleaseNote: Codable, Equatable, Identifiable {
        let version: String
        let body: String
        let publishedAt: String
        let htmlURL: String

        var id: String { version }
    }

    struct UpdateResult {
        let currentVersion: String
        let latestVersion: String
        let releaseNotes: String
        let releaseHistory: [ReleaseNote]
        let downloadURL: String
        let downloadSize: Int
        let htmlURL: String
    }

    enum CheckOutcome {
        case skipped
        case upToDate
        case updateAvailable(UpdateResult)
        case failed
    }

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: - 公开方法

    /// 检查更新（dev 版本默认跳过；手动检查可通过 allowDevBuild 请求远端）
    /// 距上次检查不足 24 小时且 force=false 时跳过网络请求
    func checkForUpdate(force: Bool = false, allowDevBuild: Bool = false) async -> UpdateResult? {
        if case .updateAvailable(let result) = await checkOutcome(
            force: force,
            allowDevBuild: allowDevBuild
        ) {
            return result
        }
        return nil
    }

    /// 与 `checkForUpdate` 相同，但区分“无需联网检查”“已是最新”和“检查失败”。
    func checkOutcome(force: Bool = false, allowDevBuild: Bool = false) async -> CheckOutcome {
        let startedAt = CFAbsoluteTimeGetCurrent()
        var outcome = "unknown"
        defer {
            log.info(
                "更新检查结束",
                event: "update.check.completed",
                metadata: [
                    "force": String(force),
                    "allow_dev_build": String(allowDevBuild),
                    "outcome": outcome
                ],
                durationMilliseconds: Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
            )
        }

        guard !isDevBuild || allowDevBuild else {
            outcome = "skipped_dev_build"
            log.info("开发版本，跳过更新检查", event: "update.check.skipped_dev_build")
            return .skipped
        }

        let now = Date()
        if !force {
            let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
            if now.timeIntervalSince(lastCheck) < checkInterval {
                outcome = "skipped_interval"
                log.info("距上次检查不足 24 小时，跳过", event: "update.check.skipped_interval")
                return .skipped
            }
        }

        guard let releases = await fetchRecentReleases(limit: 3),
              let release = releases.first else {
            outcome = "fetch_failed"
            return .failed
        }

        UserDefaults.standard.set(now, forKey: lastCheckKey)
        cacheResult(releases)

        let currentVersion = currentVersionString()
        guard Self.isNewer(tag: release.tag_name, than: currentVersion) else {
            outcome = "up_to_date"
            log.info(
                "已是最新版本",
                event: "update.check.up_to_date",
                metadata: ["current_version": currentVersion]
            )
            return .upToDate
        }

        // 找 DMG asset（文件名以 .dmg 结尾）
        guard let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            outcome = "missing_dmg"
            log.error("Release 中没有找到 DMG 文件", event: "update.check.missing_dmg")
            return .failed
        }

        outcome = "update_available"
        return .updateAvailable(UpdateResult(
            currentVersion: currentVersion,
            latestVersion: Self.displayVersion(release.tag_name),
            releaseNotes: release.body ?? "",
            releaseHistory: Self.releaseNotes(from: releases),
            downloadURL: dmg.browser_download_url,
            downloadSize: dmg.size,
            htmlURL: release.html_url
        ))
    }

    // MARK: - 缓存上次检查结果

    private let lastReleaseNotesKey = "PastryLastReleaseNotes"
    private let lastCheckedVersionKey = "PastryLastCheckedVersion"
    private let releaseHistoryKey = "PastryReleaseHistory"

    /// 缓存成功的检查结果（供 upToDate 页显示上次更新日志）
    private func cacheResult(_ results: [ReleaseInfo]) {
        let notes = Self.releaseNotes(from: results)
        UserDefaults.standard.set(notes.first?.body, forKey: lastReleaseNotesKey)
        UserDefaults.standard.set(notes.first?.version, forKey: lastCheckedVersionKey)
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: releaseHistoryKey)
        }
    }

    /// 读取缓存的 release notes
    func cachedReleaseNotes() -> String? {
        UserDefaults.standard.string(forKey: lastReleaseNotesKey)
    }

    func cachedReleaseHistory() -> [ReleaseNote] {
        guard let data = UserDefaults.standard.data(forKey: releaseHistoryKey),
              let notes = try? JSONDecoder().decode([ReleaseNote].self, from: data) else {
            if let notes = cachedReleaseNotes(), !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let version = UserDefaults.standard.string(forKey: lastCheckedVersionKey) ?? AppVersion.displayCurrent
                return [
                    ReleaseNote(
                        version: Self.displayVersion(version),
                        body: notes,
                        publishedAt: "",
                        htmlURL: ""
                    )
                ]
            }
            return []
        }
        return notes
    }

    /// 下载二进制到临时目录，返回文件路径。onProgress 回调 0.0~1.0；调用方负责切回主线程更新 UI。
    /// expectedSize 用于 CDN 不返回 Content-Length 时的进度计算。
    func downloadBinary(from urlString: String, expectedSize: Int, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidURL
        }
        guard url.scheme?.lowercased() == "https" else {
            throw UpdateError.insecureURL
        }

        let delegate = StreamingDownloadDelegate(expectedSize: expectedSize, onProgress: onProgress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

        return try await delegate.download(from: url, using: session)
    }

    /// 应用更新：挂载 DMG → 校验签名 → 备份替换整个 .app → 重启
    func applyUpdate(dmgAt tempURL: URL, expectedVersion: String) throws {
        let targetPath = Bundle.main.bundlePath

        // 将 DMG 移到稳定路径（tempURL 可能被系统清理）
        let stableDMG = URL(fileURLWithPath: NSTemporaryDirectory() + "pastry_update.dmg")
        try? FileManager.default.removeItem(at: stableDMG)
        try FileManager.default.moveItem(at: tempURL, to: stableDMG)

        // 应用层预校验 DMG 内 .app 的签名，避免退出后才在 helper 脚本里发现签名问题。
        // 失败直接抛错，不进入 terminate 流程。
        try Self.verifyDMGSignature(at: stableDMG)

        // 写 helper 脚本：当前进程 terminate 后由它完成替换
        let scriptPath = NSTemporaryDirectory() + "pastry_update.sh"
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: stableDMG.path,
            targetPath: targetPath,
            expectedVersion: Self.displayVersion(expectedVersion)
        )

        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        // 启动 helper 并退出当前进程
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [scriptPath]
        try task.run()

        NSApp.terminate(nil)
    }

    /// 挂载 DMG 校验内部 Pastry.app 的签名与 ad-hoc 状态。
    /// 退出前预检，让 helper 脚本的签名校验从「最后兜底」变成「冗余二次校验」。
    private static func verifyDMGSignature(at dmgURL: URL) throws {
        // 挂载 DMG（nobrowse，不显示在 Finder）
        let mount = Process()
        mount.launchPath = "/usr/bin/hdiutil"
        mount.arguments = ["attach", "-noverify", "-noautoopen", "-nobrowse", dmgURL.path]
        let pipe = Pipe()
        mount.standardOutput = pipe
        try mount.run()
        mount.waitUntilExit()
        guard mount.terminationStatus == 0 else {
            throw NSError(domain: "PastryUpdate", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "DMG 挂载失败，无法预校验签名"])
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // 解析挂载点：取最后一个 /Volumes/ 行
        guard let volume = output.components(separatedBy: "\n").last(where: { $0.contains("/Volumes/") })?
                .components(separatedBy: "\t").last?
                .trimmingCharacters(in: .whitespaces),
              !volume.isEmpty else {
            throw NSError(domain: "PastryUpdate", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "无法解析 DMG 挂载点"])
        }

        defer { detachVolume(at: volume) }
        let candidate = (volume as NSString).appendingPathComponent("Pastry.app")
        guard FileManager.default.fileExists(atPath: candidate) else {
            throw NSError(domain: "PastryUpdate", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "DMG 内缺少 Pastry.app"])
        }

        // codesign --verify --deep --strict
        let verify = Process()
        verify.launchPath = "/usr/bin/codesign"
        verify.arguments = ["--verify", "--deep", "--strict", candidate]
        try verify.run()
        verify.waitUntilExit()
        guard verify.terminationStatus == 0 else {
            throw NSError(domain: "PastryUpdate", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "更新包签名校验失败，拒绝更新"])
        }

        // 拒绝 ad-hoc 签名
        let dv = Process()
        dv.launchPath = "/usr/bin/codesign"
        dv.arguments = ["-dv", candidate]
        let dvPipe = Pipe()
        dv.standardOutput = dvPipe
        dv.standardError = dvPipe
        try dv.run()
        dv.waitUntilExit()
        let dvOutput = String(data: dvPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if dvOutput.contains("Signature=adhoc") {
            throw NSError(domain: "PastryUpdate", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "更新包使用 ad-hoc 签名，拒绝更新"])
        }
    }

    private static func detachVolume(at path: String) {
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detach.arguments = ["detach", path, "-quiet"]
        do {
            try detach.run()
            detach.waitUntilExit()
        } catch {
            // helper 脚本仍会执行自己的挂载与卸载；预校验清理失败不覆盖原始校验结果。
        }
    }

    // MARK: - 版本比较

    private func currentVersionString() -> String {
        AppVersion.displayCurrent
    }

    /// 语义化版本比较：tag > current → true
    static func isNewer(tag: String, than current: String) -> Bool {
        let tagParts = Self.versionNumberParts(tag)
        let curParts = Self.versionNumberParts(current)

        for i in 0..<max(tagParts.count, curParts.count) {
            let t = i < tagParts.count ? tagParts[i] : 0
            let c = i < curParts.count ? curParts[i] : 0
            if t > c { return true }
            if t < c { return false }
        }
        return false
    }

    private static func versionNumberParts(_ version: String) -> [Int] {
        displayVersion(version).split(separator: ".").map { part in
            let digits = part.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }

    static func displayVersion(_ version: String) -> String {
        version.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^v+"#, with: "", options: .regularExpression)
    }

    static func downloadProgressForTesting(
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64,
        expectedSize: Int
    ) -> Double? {
        downloadProgress(
            totalBytesWritten: totalBytesWritten,
            totalBytesExpectedToWrite: totalBytesExpectedToWrite,
            expectedSize: expectedSize
        )
    }

    fileprivate static func downloadProgress(
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64,
        expectedSize: Int
    ) -> Double? {
        let totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(expectedSize)
        guard totalBytes > 0 else { return nil }
        let progress = Double(totalBytesWritten) / Double(totalBytes)
        return min(max(progress, 0), 0.99)
    }

    // MARK: - 网络请求

    private func fetchRecentReleases(limit: Int) async -> [ReleaseInfo]? {
        guard var components = URLComponents(string: "https://api.github.com/repos/vipic/pastry/releases") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "\(limit)")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pastry/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                log.error(
                    "GitHub Releases API 返回非成功状态",
                    event: "update.releases.http_failed",
                    metadata: [
                        "status_code": String((response as? HTTPURLResponse)?.statusCode ?? -1)
                    ]
                )
                return nil
            }
            let decoder = JSONDecoder()
            return try decoder.decode([ReleaseInfo].self, from: data)
        } catch {
            log.error(
                "获取 Releases 失败",
                event: "update.releases.failed",
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }
    }

    private func fetchLatestRelease() async -> ReleaseInfo? {
        guard let url = URL(string: "https://api.github.com/repos/vipic/pastry/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pastry/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                log.error(
                    "GitHub Release API 返回非成功状态",
                    event: "update.release.http_failed",
                    metadata: [
                        "status_code": String((response as? HTTPURLResponse)?.statusCode ?? -1)
                    ]
                )
                return nil
            }
            let decoder = JSONDecoder()
            return try decoder.decode(ReleaseInfo.self, from: data)
        } catch {
            log.error(
                "获取 Release 失败",
                event: "update.release.failed",
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }
    }

    static func releaseNotes(from releases: [ReleaseInfo]) -> [ReleaseNote] {
        releases.map {
            ReleaseNote(
                version: displayVersion($0.tag_name),
                body: $0.body ?? "",
                publishedAt: $0.published_at,
                htmlURL: $0.html_url
            )
        }
    }

    enum UpdateError: LocalizedError, Equatable {
        case invalidURL
        case insecureURL
        case downloadTooLarge
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "下载链接无效"
            case .insecureURL: return "下载链接必须使用 HTTPS"
            case .downloadTooLarge: return "下载文件超过安全大小限制"
            case .downloadFailed: return "下载失败"
            }
        }
    }

    static func downloadByteLimitForTesting(expectedSize: Int) -> Int64 {
        downloadByteLimit(expectedSize: expectedSize)
    }

    fileprivate static func downloadByteLimit(expectedSize: Int) -> Int64 {
        guard expectedSize > 0 else { return maxDownloadBytes }
        let expectedWithSlack = Int64(Double(expectedSize) * 1.10) + 1_048_576
        return min(maxDownloadBytes, max(Int64(expectedSize), expectedWithSlack))
    }
}

// MARK: - 下载进度代理
private final class StreamingDownloadDelegate: NSObject, URLSessionDataDelegate {

    private let onProgress: (@Sendable (Double) -> Void)?
    private let expectedSize: Int
    private let byteLimit: Int64
    private var lastProgress = 0.0
    private var totalBytesWritten: Int64 = 0
    private var totalBytesExpectedToWrite: Int64 = 0
    private var continuation: CheckedContinuation<URL, Error>?
    private var fileURL: URL?
    private var fileHandle: FileHandle?
    private var didReceiveSuccessfulResponse = false
    private var didFinish = false

    init(expectedSize: Int, onProgress: (@Sendable (Double) -> Void)?) {
        self.expectedSize = expectedSize
        self.onProgress = onProgress
        self.byteLimit = UpdateChecker.downloadByteLimit(expectedSize: expectedSize)
    }

    func download(from url: URL, using session: URLSession) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastry-update-\(UUID().uuidString).dmg")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)

        do {
            fileHandle = try FileHandle(forWritingTo: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        fileURL = tempURL

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.dataTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            completionHandler(.cancel)
            finish(with: UpdateChecker.UpdateError.downloadFailed)
            return
        }
        if response.expectedContentLength > byteLimit {
            completionHandler(.cancel)
            finish(with: UpdateChecker.UpdateError.downloadTooLarge)
            return
        }

        didReceiveSuccessfulResponse = true
        totalBytesExpectedToWrite = response.expectedContentLength
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard totalBytesWritten + Int64(data.count) <= byteLimit else {
            dataTask.cancel()
            finish(with: UpdateChecker.UpdateError.downloadTooLarge)
            return
        }

        do {
            try fileHandle?.write(contentsOf: data)
        } catch {
            dataTask.cancel()
            finish(with: error)
            return
        }

        totalBytesWritten += Int64(data.count)
        guard let progress = UpdateChecker.downloadProgress(
            totalBytesWritten: totalBytesWritten,
            totalBytesExpectedToWrite: totalBytesExpectedToWrite,
            expectedSize: expectedSize
        ), progress > lastProgress else {
            return
        }

        lastProgress = progress
        onProgress?(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }
        if let error {
            finish(with: error)
            return
        }
        guard didReceiveSuccessfulResponse, let fileURL else {
            finish(with: UpdateChecker.UpdateError.downloadFailed)
            return
        }

        onProgress?(1.0)
        finish(with: fileURL)
    }

    private func finish(with url: URL) {
        guard !didFinish else { return }
        didFinish = true
        closeFile()
        continuation?.resume(returning: url)
        continuation = nil
    }

    private func finish(with error: Error) {
        guard !didFinish else { return }
        didFinish = true
        closeFile()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func closeFile() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}
