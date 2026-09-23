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

    private func resolveSourceApp(for pasteboard: NSPasteboard) -> (name: String?, bundleID: String?) {
        let frontApp = NSWorkspace.shared.frontmostApplication
        guard let bundleID = Self.resolvedSourceBundleID(from: pasteboard, frontmostBundleID: frontApp?.bundleIdentifier)
        else { return (nil, nil) }
        if bundleID == "com.agilebits.onepassword", Self.isOnePasswordPasteboard(pasteboard.types) {
            return ("1Password", bundleID)
        }
        let name = bundleID == frontApp?.bundleIdentifier ? frontApp?.localizedName :
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { FileManager.default.displayName(atPath: $0.path) }
                .map { ($0 as NSString).deletingPathExtension }
        return (name ?? bundleID, bundleID)
    }

    /// 显式空来源表示未知，不等同于标记缺失；前台应用仍只是无标记时的推测。
    static func resolvedSourceBundleID(from pasteboard: NSPasteboard, frontmostBundleID: String?) -> String? {
        if pasteboard.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.source")) == true {
            return sourceBundleID(from: pasteboard)
        }
        if isOnePasswordPasteboard(pasteboard.types) { return "com.agilebits.onepassword" }
        return frontmostBundleID
    }

    static func sourceBundleID(from pasteboard: NSPasteboard) -> String? {
        let marker = NSPasteboard.PasteboardType("org.nspasteboard.source")
        guard let value = pasteboard.string(forType: marker)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
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

        processChange(from: pb, expectedChange: currentChange, shouldPlayCopyFeedback: shouldPlayCopyFeedback)
    }

    /// 只在同一代剪贴板内返回结果；后台处理只能接收已经稳定读取的内存数据。
    static func readStableValue<T>(
        from pasteboard: NSPasteboard,
        expectedChange: Int,
        read: () -> T?
    ) -> T? {
        guard pasteboard.changeCount == expectedChange else { return nil }
        let result = read()
        guard pasteboard.changeCount == expectedChange else { return nil }
        return result
    }

    private enum CapturedContent {
        case item(ClipboardItem)
        case image(NSImage, Data, String?)
        case html(Data, String, URL?, ClipboardItem?)
        case rtf(Data, ClipboardItem?)
    }

    private func processChange(from pb: NSPasteboard, expectedChange: Int, shouldPlayCopyFeedback: Bool) {
        let captured = Self.readStableValue(from: pb, expectedChange: expectedChange) {
            () -> (String?, Bool, CapturedContent)? in
            guard let types = pb.types, !types.isEmpty,
                  !Self.shouldSkipChange(bundleID: nil, pasteboardTypes: types) else { return nil }
            let source = resolveSourceApp(for: pb)
            guard !Self.shouldSkipChange(bundleID: source.bundleID, pasteboardTypes: types) else { return nil }
            let isHandoff = types.contains { $0.rawValue == "com.apple.is-remote-clipboard" }
            let appName = isHandoff ? nil : source.name
            guard let content = captureContent(from: pb, appName: appName, isHandoff: isHandoff) else { return nil }
            return (appName, isHandoff, content)
        }
        guard let (appName, isHandoff, content) = captured else { return }
        if shouldPlayCopyFeedback { SoundFeedback.play(Self.copySound) }
        switch content {
        case .item(let item):
            publish(item)
        case .image(let image, let data, let annotation):
            saveImageAndPublish(image: image, data: data, appName: appName,
                                isHandoff: isHandoff, textAnnotation: annotation)
        case .html(let data, let html, let url, let fallback):
            parseRichContentAndPublish(htmlData: data, html: html, rtfData: nil,
                                       fallbackText: fallback, appName: appName, isHandoff: isHandoff,
                                       sourceURL: url)
        case .rtf(let data, let fallback):
            parseRichContentAndPublish(htmlData: nil, html: nil, rtfData: data,
                                       fallbackText: fallback, appName: appName, isHandoff: isHandoff,
                                       sourceURL: nil)
        }
    }

    private func captureContent(from pb: NSPasteboard, appName: String?, isHandoff: Bool) -> CapturedContent? {
        if let item = readFileURLs(from: pb, appName: appName, isHandoff: isHandoff) { return .item(item) }
        if let item = readURL(from: pb, appName: appName, isHandoff: isHandoff) { return .item(item) }
        if let (image, data) = readImageData(from: pb) {
            return .image(image, data, readText(from: pb, appName: nil)?.content)
        }
        if let data = pb.data(forType: .html), let html = String(data: data, encoding: .utf8) {
            return .html(data, html, readChromiumSourceURL(from: pb),
                         readText(from: pb, appName: appName, isHandoff: isHandoff))
        }
        if let data = pb.data(forType: .rtf) {
            return .rtf(data, readText(from: pb, appName: appName, isHandoff: isHandoff))
        }
        return readText(from: pb, appName: appName, isHandoff: isHandoff).map(CapturedContent.item)
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

    // MARK: - 采集前过滤（供 production 与测试共用）

    /// 按通用约定跳过敏感、临时中转与非主动复制的自动生成内容。
    private static let ignoredRawTypeNames: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
    ]

    /// 是否跳过本次剪贴板变化（排除名单内的来源 App，或带敏感标记的 pasteboard）。
    /// `processChange` 只在该判定为 false 时继续采集。
    static func shouldSkipChange(
        bundleID: String?,
        pasteboardTypes: [NSPasteboard.PasteboardType]?
    ) -> Bool {
        if let bundleID {
            let excluded = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
            if excluded.contains(bundleID) {
                return true
            }
        }

        guard let pasteboardTypes else { return false }
        return pasteboardTypes.contains { ignoredRawTypeNames.contains($0.rawValue) }
    }

    /// 1Password Quick Open 会在 pasteboard 上带自己的类型，据此识别来源。
    static func isOnePasswordPasteboard(_ pasteboardTypes: [NSPasteboard.PasteboardType]?) -> Bool {
        pasteboardTypes?.contains { $0.rawValue == "com.agilebits.onepassword" } ?? false
    }
}
