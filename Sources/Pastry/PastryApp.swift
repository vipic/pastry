import SwiftUI
import OSLog
import ServiceManagement

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Onboarding {
        static let windowHeight: CGFloat = 480
    }
    enum Settings {
        static let windowHeight: CGFloat = 660
        static let windowWidth: CGFloat = 880
    }
}

@MainActor
enum OnboardingWindowChrome {
    static func hideTrafficLightButtons(in window: NSWindow) {
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for buttonType in buttonTypes {
            window.standardWindowButton(buttonType)?.isHidden = true
        }
    }
}

// MARK: - 应用委托
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 静态引用 — 避免依赖 NSApp.delegate 的时机不确定性
    nonisolated(unsafe) static private(set) weak var shared: AppDelegate?

    private var settingsWindow: NSWindow?
    private var helpWindow: NSWindow?
    private var updateWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var onboardingStep: OnboardingStep?
    private var onboardingKeyMonitor: Any?
    private var onboardingOverlayHandoff: OnboardingOverlayHandoff?
    private var shouldOpenOverlayAfterOnboarding = false
    private let updateErrorPath = "/tmp/pastry_update_error.txt"
    private let diagnosticsLog = PastryLogger(category: "app")

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    // MARK: - NSApplicationDelegate

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动主线程看门狗（卡死时自动 dump 堆栈）
        MainThreadWatchdog.shared.start()
        configureApplicationIcon()

        // About / Settings 由 SwiftUI commands 替换默认系统项。
        // 这里仅保留系统菜单中仍需 AppKit 级别重定向的条目。
        if let helpMenu = NSApp.mainMenu?.items.last(where: { $0.title == L10n["menu.help"] })?.submenu {
            if let helpItem = helpMenu.items.first {
                helpItem.action = #selector(showHelpWindow)
                helpItem.target = self
            }
        }

        // 将 Edit > Find > "Find…" (⌘F) 重定向到搜索栏聚焦
        // NSEvent local monitor 已在 OverlayPanelManager 拦截 ⌘F 做搜索栏聚焦，
        // 此处让菜单条目显示快捷键并支持鼠标点击触发
        if let editMenu = NSApp.mainMenu?.item(at: 2)?.submenu {
            for item in editMenu.items {
                if let findSubmenu = item.submenu,
                   let findItem = findSubmenu.items.first(where: {
                    $0.keyEquivalent == "f" && $0.keyEquivalentModifierMask == .command
                }) {
                    findItem.action = #selector(focusSearchField)
                    findItem.target = self
                    break
                }
            }
        }

        // 初次启动：写入常见密码管理器的默认排除名单
        seedDefaultExcludedApps()
        showPendingUpdateErrorIfNeeded()
        showOnboardingIfNeeded()
        diagnosticsLog.info(
            "应用完成启动",
            event: "app.did_finish_launching",
            metadata: ["onboarding_required": String(OnboardingPreferences.needsPresentation())]
        )
    }

    private func configureApplicationIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else { return }
        NSApp.applicationIconImage = icon
    }

    func applicationWillTerminate(_ notification: Notification) {
        diagnosticsLog.info("应用即将退出", event: "app.will_terminate")
        MainThreadWatchdog.shared.stop()
        DeveloperDiagnostics.flush()
    }

    @MainActor
    @objc func openSettingsWindow() {
        openSettingsWindow(selectedTab: .general)
    }

    @MainActor
    func openSettingsWindow(selectedTab: SettingsSceneView.SettingsTab) {
        // 先关闭面板，否则面板层级高于设置窗口会遮挡
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .settingsSelectTab, object: selectedTab.rawValue)
            return
        }

        let savedPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Local.Settings.windowWidth,
                height: Local.Settings.windowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "Pastry"
        window.title = appName
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsSceneView(initialTab: selectedTab))

        let delegate = SettingsWindowDelegate(savedPolicy: savedPolicy)
        window.delegate = delegate
        delegate.selfRetain()
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    @objc func showAboutWindow() {
        openSettingsWindow(selectedTab: .about)
    }

    @MainActor
    func showOnboardingIfNeeded() {
        guard OnboardingPreferences.needsPresentation() else { return }
        showOnboardingWindow()
    }

    @MainActor
    @objc func showOnboardingWindow() {
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        OverlayPanelManager.shared.hide()
        let savedPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: UIConstants.Onboarding.windowWidth,
                height: Local.Onboarding.windowHeight
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n["onboarding.window_title"]
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        OnboardingWindowChrome.hideTrafficLightButtons(in: window)
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        onboardingStep = .welcome
        shouldOpenOverlayAfterOnboarding = false
        window.contentView = NSHostingView(
            rootView: OnboardingView(
                onStepChange: { [weak self] step in
                    self?.onboardingStep = step
                },
                onFinish: { [weak self, weak window] openOverlay in
                    self?.shouldOpenOverlayAfterOnboarding = openOverlay
                    window?.close()
                }
            )
        )

        let delegate = SettingsWindowDelegate(savedPolicy: savedPolicy) { [weak self] in
            OnboardingPreferences.markCompleted()
            self?.onboardingWindow = nil
            self?.onboardingStep = nil
            self?.stopOnboardingShortcutMonitor()
        } restorePolicy: { [weak self] savedPolicy in
            if let self {
                self.restorePolicyAfterOnboarding(savedPolicy)
            } else {
                NSApp.setActivationPolicy(savedPolicy)
            }
        }
        window.delegate = delegate
        delegate.selfRetain()
        onboardingWindow = window
        startOnboardingShortcutMonitor()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func restorePolicyAfterOnboarding(_ savedPolicy: NSApplication.ActivationPolicy) {
        guard shouldOpenOverlayAfterOnboarding else {
            NSApp.setActivationPolicy(savedPolicy)
            return
        }

        shouldOpenOverlayAfterOnboarding = false
        let handoff = OnboardingOverlayHandoff()
        onboardingOverlayHandoff = handoff
        handoff.restorePolicyAndOpen(
            savedPolicy: savedPolicy,
            isApplicationActive: { NSApp.isActive },
            restorePolicy: { NSApp.setActivationPolicy(savedPolicy) },
            openOverlay: { [weak self] in
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    OverlayPanelManager.shared.show()
                    self?.onboardingOverlayHandoff = nil
                }
            }
        )
    }

    @MainActor
    var isOnboardingShortcutStepVisible: Bool {
        onboardingWindow?.isVisible == true && onboardingStep == .shortcut
    }

    @MainActor
    func acknowledgeOnboardingActivation(source: OnboardingActivationSource) -> Bool {
        guard let window = onboardingWindow, isOnboardingShortcutStepVisible else { return false }
        NotificationCenter.default.post(name: .onboardingActivationDetected, object: source)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    @MainActor
    private func startOnboardingShortcutMonitor() {
        stopOnboardingShortcutMonitor()
        onboardingKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.onboardingWindow?.isVisible == true,
                  GlobalHotkeyManager.shared.matchesCurrentShortcut(event)
            else { return event }

            return self.acknowledgeOnboardingActivation(source: .shortcut) ? nil : event
        }
    }

    @MainActor
    private func stopOnboardingShortcutMonitor() {
        guard let onboardingKeyMonitor else { return }
        NSEvent.removeMonitor(onboardingKeyMonitor)
        self.onboardingKeyMonitor = nil
    }

    @MainActor
    @objc func showHelpWindow() {
        if let existing = helpWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let savedPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n["menu.help"]
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HelpView())

        let delegate = SettingsWindowDelegate(savedPolicy: savedPolicy)
        window.delegate = delegate
        delegate.selfRetain()
        helpWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    @objc func showUpdateWindow() {
        if let existing = updateWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let savedPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pastry"
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        window.isReleasedWhenClosed = false

        // 初始显示"检查中"状态
        let hostingView = NSHostingView(rootView: UpdateView(state: .checking, releaseNotes: nil, currentVersion: nil, latestVersion: nil, onCancel: { [weak window] in
            window?.close()
        }))
        window.contentView = hostingView

        let delegate = SettingsWindowDelegate(savedPolicy: savedPolicy)
        window.delegate = delegate
        delegate.selfRetain()
        updateWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 异步检查更新
        Task { @MainActor in
            if let result = await UpdateChecker.shared.checkForUpdate(force: true, allowDevBuild: true) {
                let notes = result.releaseNotes
                hostingView.rootView = UpdateView(
                    state: .updateAvailable(result: result),
                    releaseNotes: notes,
                    currentVersion: result.currentVersion,
                    latestVersion: result.latestVersion,
                    onUpdate: { [weak window, weak hostingView] in
                        guard let window, let hostingView else { return }
                        Task { @MainActor in
                            await self.performUpdateFlow(result: result, notes: notes, curVersion: result.currentVersion, latVersion: result.latestVersion, hostingView: hostingView, window: window)
                        }
                    },
                    onCancel: { [weak window] in
                        window?.close()
                    }
                )
            } else {
                let lastCheck = UserDefaults.standard.object(forKey: "PastryLastUpdateCheck") as? Date
                let cachedNotes = UpdateChecker.shared.cachedReleaseNotes()
                hostingView.rootView = UpdateView(
                    state: .upToDate(
                        version: AppVersion.displayCurrent,
                        build: AppVersion.displayBuild,
                        lastCheckDate: lastCheck,
                        lastReleaseNotes: cachedNotes
                    ),
                    releaseNotes: cachedNotes,
                    currentVersion: nil,
                    latestVersion: nil,
                    onCancel: { [weak window] in
                        window?.close()
                    }
                )
            }
        }
    }

    /// 下载 → 安装 → 重启，全程窗口保持可见并更新进度
    @MainActor
    private func performUpdateFlow(result: UpdateChecker.UpdateResult,
                                   notes: String,
                                   curVersion: String,
                                   latVersion: String,
                                   hostingView: NSHostingView<UpdateView>,
                                   window: NSWindow) async {
        // 切换到下载中
        hostingView.rootView = UpdateView(
            state: .downloading(progress: 0),
            releaseNotes: notes,
            currentVersion: curVersion,
            latestVersion: latVersion,
            onCancel: { [weak window] in
                window?.close()
            }
        )

        do {
            let tempURL = try await UpdateChecker.shared.downloadBinary(
                from: result.downloadURL,
                expectedSize: result.downloadSize,
                onProgress: { [weak hostingView, notes, curVersion, latVersion] progress in
                    DispatchQueue.main.async {
                        hostingView?.rootView = UpdateView(
                            state: .downloading(progress: progress),
                            releaseNotes: notes,
                            currentVersion: curVersion,
                            latestVersion: latVersion,
                            onCancel: { [weak window] in window?.close() }
                        )
                    }
                }
            )

            // 切换到安装中
            hostingView.rootView = UpdateView(
                state: .installing,
                releaseNotes: notes,
                currentVersion: curVersion,
                latestVersion: latVersion,
                onCancel: nil
            )

            try UpdateChecker.shared.applyUpdate(dmgAt: tempURL, expectedVersion: result.latestVersion)
        } catch {
            let log = Logger(subsystem: "com.nekutai.pastry", category: "update")
            log.error("更新失败: \(error.localizedDescription)")
            diagnosticsLog.error(
                "更新安装失败",
                event: "update.install.failed",
                metadata: ["error": error.localizedDescription]
            )
            hostingView.rootView = UpdateView(
                state: .error(error.localizedDescription),
                releaseNotes: nil,
                currentVersion: nil,
                latestVersion: nil,
                onCancel: { [weak window] in window?.close() }
            )
        }
    }

    @MainActor
    private func showPendingUpdateErrorIfNeeded() {
        let url = URL(fileURLWithPath: updateErrorPath)
        guard let message = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else { return }

        try? FileManager.default.removeItem(at: url)
        showUpdateErrorWindow(message: message)
    }

    @MainActor
    private func showUpdateErrorWindow(message: String) {
        if let existing = updateWindow, existing.isVisible {
            existing.close()
        }

        let savedPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pastry"
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UpdateView(
            state: .error(message),
            releaseNotes: nil,
            currentVersion: nil,
            latestVersion: nil,
            onCancel: { [weak window] in
                window?.close()
            }
        ))

        let delegate = SettingsWindowDelegate(savedPolicy: savedPolicy)
        window.delegate = delegate
        delegate.selfRetain()
        updateWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 搜索栏聚焦（Edit > Find 菜单）

    /// 将 ⌘F / Edit > Find 菜单重定向到搜索栏（面板打开时有效）
    @objc func focusSearchField() {
        NotificationCenter.default.post(name: .overlayOpenSearch, object: nil)
    }

    // MARK: - 默认排除名单

    /// 初次启动时，检测已安装的常见密码管理器，写入排除名单。
    /// 未安装的应用不写入，避免在设置界面显示无效条目。
    private func seedDefaultExcludedApps() {
        let seededKey = "excluded_apps_seeded"
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        UserDefaults.standard.set(true, forKey: seededKey)

        let candidates: [String] = [
            "com.1password.1password",           // 1Password
            "com.bitwarden.desktop",             // Bitwarden
            "com.apple.keychainaccess",           // 钥匙串访问
            "org.keepassxc.keepassxc",            // KeePassXC
            "com.lastpass.lastpass",              // LastPass
            "com.dashlane.dashlane",              // Dashlane
            "com.agilebits.onepassword7",        // 1Password 7
        ]

        let installed = candidates.filter { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                return false
            }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        guard !installed.isEmpty else { return }

        var current = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        for id in installed where !current.contains(id) {
            current.append(id)
        }
        UserDefaults.standard.set(current, forKey: UserDefaultsKeys.excludedBundleIDs)

        let joined = installed.joined(separator: ", ")
        Logger(subsystem: "com.nekutai.pastry", category: "app")
            .info("默认排除名单已写入: \(joined)")
    }
}

// 关闭设置时恢复后台模式
private class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    let savedPolicy: NSApplication.ActivationPolicy
    private let onClose: (() -> Void)?
    private let restorePolicy: ((NSApplication.ActivationPolicy) -> Void)?
    private var selfReference: SettingsWindowDelegate?

    init(
        savedPolicy: NSApplication.ActivationPolicy,
        onClose: (() -> Void)? = nil,
        restorePolicy: ((NSApplication.ActivationPolicy) -> Void)? = nil
    ) {
        self.savedPolicy = savedPolicy
        self.onClose = onClose
        self.restorePolicy = restorePolicy
    }

    func selfRetain() { selfReference = self }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        if let restorePolicy {
            restorePolicy(savedPolicy)
        } else {
            NSApp.setActivationPolicy(savedPolicy)
        }
        selfReference = nil
    }
}

// MARK: - 应用入口
@main
struct PastryApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    @StateObject private var store = StoreManager.shared

    @AppStorage(UserDefaultsKeys.launchAtLogin)
    private var launchAtLogin = false

    private let log = PastryLogger(category: "app")

    /// 性能基准模式：`Pastry --bench` 跑完初始化输出耗时后退出
    private static let isBenchmark = CommandLine.arguments.contains("--bench")

    init() {
        let initializationStart = CFAbsoluteTimeGetCurrent()

        store.start()

        // 清理孤儿图片缓存（数据库中已删除但缓存文件还在的 .png + .orig）
        ImageCacheManager.shared.cleanupOrphans(activePaths: DatabaseManager.shared.allImageContentPaths())

        if Self.isBenchmark {
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - initializationStart) * 1000)
            log.info(
                "启动基准完成",
                event: "app.benchmark.completed",
                durationMilliseconds: elapsed
            )
            DeveloperDiagnostics.flush()
            exit(0)
        }

        // 后台预热近期应用图标/主题色，避免首次打开托盘时卡片同步抽色卡动画。
        // Finder 不在 availableApps 里（筛选列表刻意排除），但从 Finder 复制文件时首卡几乎总是它。
        let appsToWarm = store.availableApps
        Task.detached(priority: .utility) {
            _ = AppIconProvider.shared.themeColor(for: "Finder")
            for app in appsToWarm.prefix(32) {
                _ = AppIconProvider.shared.themeColor(for: app)
            }
        }

        GlobalHotkeyManager.shared.register()
        MenuBarManager.shared.setup()

        // 下一 runloop 预热面板管线（不挡启动）；用户第一次打开时应已走过 Hosting/玻璃首帧
        DispatchQueue.main.async {
            OverlayPanelManager.shared.warmupPipelineIfNeeded()
        }

        log.info(
            "Pastry 初始化完成",
            event: "app.initialization.completed",
            metadata: ["item_count": String(store.items.count)],
            durationMilliseconds: Int((CFAbsoluteTimeGetCurrent() - initializationStart) * 1000)
        )
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("\(L10n["menu.about"]) Pastry") {
                    appDelegate.showAboutWindow()
                }

                Button(L10n["menu.check_updates"]) {
                    appDelegate.openSettingsWindow(selectedTab: .version)
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button(L10n["menu.settings"]) {
                    appDelegate.openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button(L10n["menu.help"]) {
                    appDelegate.showHelpWindow()
                }

                Button(L10n["menu.onboarding"]) {
                    appDelegate.showOnboardingWindow()
                }
            }
        }
    }
}
