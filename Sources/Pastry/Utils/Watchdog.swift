import Foundation
import OSLog

// MARK: - 主线程看门狗
// 后台线程周期性 ping 主线程，超时无响应则自动 sample 进程并写堆栈到文件
final class MainThreadWatchdog {

    static let shared = MainThreadWatchdog()

    private let log = PastryLogger(category: "watchdog")
    private let pingInterval: TimeInterval = 2.0    // 每 2s 发一次 ping
    private let hangThreshold: TimeInterval = 5.0    // 5s 无响应视为卡死
    /// 同一轮卡死最多每 30s 采一次样：`sample` 要采样 1 秒且会阻塞协作线程，
    /// 逐 tick 触发会在最需要轻载的卡死现场叠加成样本风暴并写满 HangReports。
    private let minimumSampleInterval: TimeInterval = 30
    private let dumpDir: URL

    private var timer: DispatchSourceTimer?
    private var lastPong = Date.distantFuture
    private var lastSampleAt: Date?
    private let lock = NSLock()

    private init() {
        dumpDir = AppDirectories.applicationSupportDirectory()
            .appendingPathComponent("HangReports")
        AppDirectories.ensureDirectory(dumpDir, logCategory: "watchdog")
    }

    func start() {
        guard timer == nil else { return }

        lastPong = Date()
        let queue = DispatchQueue(label: "com.nekutai.pastry.watchdog")

        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        timer?.setEventHandler { [weak self] in
            self?.tick()
        }
        timer?.resume()

        log.info(
            "主线程看门狗已启动",
            event: "watchdog.started",
            metadata: [
                "ping_interval_ms": String(Int(pingInterval * 1_000)),
                "hang_threshold_ms": String(Int(hangThreshold * 1_000))
            ]
        )
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - 私有

    /// 后台线程定时回调：ping 主线程，检查是否超时
    private func tick() {
        let pingTime = Date()

        // 发 ping 给主线程
        DispatchQueue.main.async { [weak self] in
            self?.lock.withLock {
                self?.lastPong = Date()
            }
        }

        // 延迟 threshold 后检查主线程是否响应
        Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(self?.hangThreshold ?? 5.0))
            guard let self else { return }
            let lastResponse = self.lock.withLock { self.lastPong }
            if lastResponse < pingTime {
                self.sampleProcessIfDue(reason: "主线程 \(Int(self.hangThreshold))s 无响应")
                // 自救：强制关闭遮挡整个屏幕的面板，解除全屏遮罩让鼠标事件穿透。
                self.recoverEventSystem()
            }
        }
    }

    /// 采样节流：已有采样在近期跑过就跳过，避免卡死期间每个 tick 起一个 `sample` 进程。
    private func sampleProcessIfDue(reason: String) {
        let now = Date()
        let isDue = lock.withLock { () -> Bool in
            if let lastSampleAt, now.timeIntervalSince(lastSampleAt) < minimumSampleInterval {
                return false
            }
            lastSampleAt = now
            return true
        }
        guard isDue else { return }
        sampleProcess(reason: reason)
    }

    /// 强制恢复事件系统（可在任意线程调用，不依赖主线程）。
    /// 关闭 overlay 面板，解除全屏遮罩。
    private func recoverEventSystem() {
        log.warning("看门狗检测到主线程无响应，关闭面板自救", event: "watchdog.recovery.started")
        DispatchQueue.main.async {
            OverlayPanelManager.shared.hide()
        }
    }

    /// 调用 /usr/bin/sample 采集进程堆栈，写入文件
    private func sampleProcess(reason: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safeName = timestamp.replacingOccurrences(of: ":", with: "-")
        let filename = "hang_\(safeName).txt"
        let fileURL = dumpDir.appendingPathComponent(filename)

        let pid = ProcessInfo.processInfo.processIdentifier

        let task = Process()
        task.launchPath = "/usr/bin/sample"
        task.arguments = ["\(pid)", "1", "-file", fileURL.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            if FileManager.default.fileExists(atPath: fileURL.path) {
                log.critical(
                    "主线程无响应，sample 已写入",
                    event: "watchdog.sample.succeeded",
                    metadata: ["reason": reason, "report_path": fileURL.path]
                )
            } else {
                log.critical(
                    "主线程无响应，sample 命令执行失败",
                    event: "watchdog.sample.failed",
                    metadata: ["reason": reason]
                )
            }
        } catch {
            log.error(
                "看门狗 sample 启动失败",
                event: "watchdog.sample.launch_failed",
                metadata: ["error": error.localizedDescription]
            )
        }
    }
}
