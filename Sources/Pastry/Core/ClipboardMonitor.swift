import Cocoa
import Combine
import OSLog

// MARK: - 剪贴板监听器
// 核心策略：50ms 定时器轮询 NSPasteboard.changeCount，检测变化后立即读取。
// 不使用 CGEvent tap（全键盘监听），避免隐私顾虑和系统事件链阻塞风险。
final class ClipboardMonitor: ObservableObject {

    // MARK: 单例
    nonisolated(unsafe) static let shared = ClipboardMonitor()

    // MARK: Published
    @Published private(set) var latestItem: ClipboardItem?
    @Published private(set) var isRunning = false

    // MARK: 回调
    var onNewItem: ((ClipboardItem) -> Void)?

    // MARK: 私有状态
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var ignoredChangeCounts: Set<Int> = []
    /// Pastry 自身的复制入口会立即播放反馈；监听器仍处理该变更，但不重复播音。
    private var copyFeedbackPlayedChangeCounts: Set<Int> = []
    private var timer: Timer?
    private let pollInterval: TimeInterval = 0.05   // 50ms，人耳无法感知延迟
    private let log = PastryLogger(category: "monitor")

    /// 自定义复制提示音
    private static let copySound: NSSound? = {
        guard let path = Bundle.main.path(forResource: "Copy", ofType: "aiff") else {
            PastryLogger(category: "monitor").warning(
                "找不到复制提示音资源",
                event: "monitor.copy_sound.missing"
            )
            return nil
        }
        let sound = NSSound(contentsOfFile: path, byReference: true)
        // 启动时预暖音频管线，避免首次复制的 play() 冷启动延迟。
        sound?.play()
        sound?.stop()
        return sound
    }()

    /// 暂停/恢复监听（仅主线程调用）
    private var suspendCount = 0
    var isSuspended: Bool { suspendCount > 0 }

    func suspend() {
        assert(Thread.isMainThread, "suspend() 必须在主线程调用")
        suspendCount += 1
    }

    func resume() {
        assert(Thread.isMainThread, "resume() 必须在主线程调用")
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        if suspendCount == 0 {
            lastChangeCount = NSPasteboard.general.changeCount
        }
    }

    /// 清空剪贴板后同步计数器，避免监听器误检
    func syncChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// 标记当前剪贴板变更为 Pastry 自己写入，避免粘贴动作被当成一次复制并播放 Copy 音效。
    func ignoreCurrentChange() {
        let changeCount = NSPasteboard.general.changeCount
        ignoredChangeCounts.insert(changeCount)
        lastChangeCount = changeCount
    }

    /// Pastry 自身的 ⌘C / 工具栏 / 右键复制入口在写入成功后调用。
    /// 先播放反馈，之后监听器仍会解析与入库，但不会再播一次。
    func playCopyFeedbackForCurrentChange() {
        assert(Thread.isMainThread, "复制反馈必须在主线程播放")
        // 50ms 内连续复制时中间 changeCount 可能不会被 poll 观测，只保留最新值避免集合累积。
        copyFeedbackPlayedChangeCounts = [NSPasteboard.general.changeCount]
        SoundFeedback.play(Self.copySound)
    }

    private init() {}

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }
        isRunning = true
        _ = Self.copySound

        lastChangeCount = NSPasteboard.general.changeCount

        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        log.info(
            "剪贴板监听已启动",
            event: "monitor.started",
            metadata: ["poll_interval_ms": String(Int(pollInterval * 1_000))]
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        log.info("剪贴板监听已停止", event: "monitor.stopped")
    }

    // MARK: - 轮询

    /// 来源检测：前台 App（`NSWorkspace.shared.frontmostApplication`）
    private func resolveSourceApp() -> (name: String?, bundleID: String?) {
        let frontApp = NSWorkspace.shared.frontmostApplication
        return (frontApp?.localizedName, frontApp?.bundleIdentifier)
    }

    private func poll() {
        guard !isSuspended else { return }

        let pb = NSPasteboard.general
        let currentChange = pb.changeCount

        guard currentChange != lastChangeCount else { return }
        lastChangeCount = currentChange
        if ignoredChangeCounts.remove(currentChange) != nil {
            return
        }
        let shouldPlayCopyFeedback = copyFeedbackPlayedChangeCounts.remove(currentChange) == nil

        var (capturedApp, capturedBundleID) = resolveSourceApp()

        // 1Password Quick Open 在 pasteboard 上写 com.agilebits.onepassword 自定义类型。
        // 用它覆写来源——比 frontmostApplication 更可靠。
        if let types = pb.types, types.contains(where: { $0.rawValue == "com.agilebits.onepassword" }) {
            capturedApp = "1Password"
            capturedBundleID = "com.agilebits.onepassword"
        }

        DispatchQueue.main.async {
            [weak self] in
            self?.processChange(
                capturedApp: capturedApp,
                capturedBundleID: capturedBundleID,
                shouldPlayCopyFeedback: shouldPlayCopyFeedback
            )
        }
    }

    // MARK: - 处理剪贴板变化

    private func processChange(
        capturedApp: String?,
        capturedBundleID: String?,
        shouldPlayCopyFeedback: Bool
    ) {
        // 排除名单：密码管理器等敏感应用不保存剪贴板历史
        if let bundleID = capturedBundleID {
            let excluded = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
            if excluded.contains(bundleID) {
                return
            }
        }

        let pb = NSPasteboard.general

        // 排除敏感 pasteboard 类型
        if let pbTypes = pb.types {
            let ignoredRawTypes: Set<String> = [
                "org.nspasteboard.ConcealedType",
            ]
            let hasIgnored = pbTypes.contains(where: { ignoredRawTypes.contains($0.rawValue) })
            if hasIgnored {
                return
            }
        }

        guard let types = pb.types, !types.isEmpty else {
            return
        }

        // 类型非空，确认有效复制 → 播提示音
        if shouldPlayCopyFeedback {
            SoundFeedback.play(Self.copySound)
        }

        // 检测 Handoff/通用剪贴板来源
        let isRemoteClipboard = types.contains(where: { $0.rawValue == "com.apple.is-remote-clipboard" })
        let effectiveApp = isRemoteClipboard ? nil : capturedApp  // Handoff 时不给 appName，之后 UI 层特殊处理

        // 文件 URL 优先：Finder 复制文件时剪贴板同时有图片数据，fileURL 更能代表用户意图
        if let item = readFileURLs(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard) {
            publish(item)
            return
        }

        // URL 链接：在图片之前检测，避免 http 字符串被当作纯文本
        if let item = readURL(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard) {
            publish(item)
            return
        }

        // 图片处理：主线程读取数据，后台任务生成缩略图并写入磁盘
        if let (image, data) = readImageData(from: pb) {
            let textAnnotation = readText(from: pb, appName: nil)?.content
            saveImageAndPublish(
                image: image,
                data: data,
                appName: effectiveApp,
                isHandoff: isRemoteClipboard,
                textAnnotation: textAnnotation
            )
            return
        }

        if let htmlData = pb.data(forType: .html),
           let html = String(data: htmlData, encoding: .utf8) {
            let sourceURL = readChromiumSourceURL(from: pb)
            let fallbackText = readText(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard)
            parseRichContentAndPublish(
                htmlData: htmlData,
                html: html,
                rtfData: nil,
                fallbackText: fallbackText,
                appName: effectiveApp,
                isHandoff: isRemoteClipboard,
                sourceURL: sourceURL
            )
            return
        }

        if let rtfData = pb.data(forType: .rtf) {
            let fallbackText = readText(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard)
            parseRichContentAndPublish(
                htmlData: nil,
                html: nil,
                rtfData: rtfData,
                fallbackText: fallbackText,
                appName: effectiveApp,
                isHandoff: isRemoteClipboard,
                sourceURL: nil
            )
            return
        }

        if let item = readText(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard) {
            publish(item)
        }
    }

    private func parseRichContentAndPublish(
        htmlData: Data?,
        html: String?,
        rtfData: Data?,
        fallbackText: ClipboardItem?,
        appName: String?,
        isHandoff: Bool,
        sourceURL: URL?
    ) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let item: ClipboardItem?
            if let htmlData, let html {
                item = self.readHTMLData(
                    htmlData,
                    html: html,
                    sourceURL: sourceURL,
                    appName: appName,
                    isHandoff: isHandoff
                )
            } else if let rtfData {
                item = self.readRTFData(rtfData, appName: appName, isHandoff: isHandoff)
            } else {
                item = nil
            }

            guard let item = item ?? fallbackText else { return }
            await self.publishOnMain(item)
        }
    }

    @MainActor
    private func publishOnMain(_ item: ClipboardItem) {
        latestItem = item
        onNewItem?(item)
    }

    private func publish(_ item: ClipboardItem) {
        DispatchQueue.main.async { [weak self] in
            self?.publishOnMain(item)
        }
    }

    private func saveImageAndPublish(
        image: NSImage,
        data: Data,
        appName: String?,
        isHandoff: Bool,
        textAnnotation: String?
    ) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let savedPath = ImageCacheManager.shared.save(image: image, data: data) else {
                self.log.error("图片缓存写入失败", event: "monitor.image_cache_write.failed")
                return
            }
            let item = ClipboardItem(
                content: savedPath,
                sourceFormat: .image,
                appName: appName,
                isHandoff: isHandoff,
                textAnnotation: textAnnotation
            )
            await self.publishOnMain(item)
        }
    }

    // MARK: - 测试入口

    /// 供单元测试：检查 bundleID 是否在排除名单中
    static func isBundleIDExcludedForTesting(_ bundleID: String) -> Bool {
        let excluded = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        return excluded.contains(bundleID)
    }

    /// 供单元测试：检测 pasteboard types 是否含 ConcealedType
    static func hasConcealedTypeForTesting(from pb: NSPasteboard) -> Bool {
        guard let types = pb.types else { return false }
        return types.contains(where: { $0.rawValue == "org.nspasteboard.ConcealedType" })
    }

    /// 供单元测试：检测 pasteboard types 是否含 1Password 标记
    static func has1PasswordTypeForTesting(from pb: NSPasteboard) -> Bool {
        guard let types = pb.types else { return false }
        return types.contains(where: { $0.rawValue == "com.agilebits.onepassword" })
    }

}
