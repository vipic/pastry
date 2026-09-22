import Cocoa
import Carbon
import OSLog

// MARK: - 全局快捷键管理器
// 使用 Carbon RegisterEventHotKey 注册系统级热键
// 即使 App 在后台也能响应
final class GlobalHotkeyManager {

    nonisolated(unsafe) static let shared = GlobalHotkeyManager()
    private let log = PastryLogger(category: "hotkey")

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var lastAppliedConfiguration: Configuration?

    struct Configuration: Equatable {
        let keyCode: Int32
        let modifiers: UInt32
    }

    // 默认快捷键: ⌘⇧V
    static let defaultKeyCode: Int32 = 9       // kVK_ANSI_V
    static let defaultModifiers: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)

    /// keyCode = -1 表示快捷键已禁用
    static let disabledSentinel: Int32 = -1

    /// 当前生效的快捷键 — 从 UserDefaults 读取
    private var currentKeyCode: Int32 {
        // object(forKey:) 区分「未设置」(nil) 与「设置为 0」(keyCode 0 是 A 键)
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.hotkeyKeyCode) == nil {
            return Self.defaultKeyCode
        }
        let raw = UserDefaults.standard.integer(forKey: UserDefaultsKeys.hotkeyKeyCode)
        return Int32(raw)
    }

    private var currentModifiers: UInt32 {
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.hotkeyModifiers) == nil {
            return Self.defaultModifiers
        }
        let raw = UserDefaults.standard.integer(forKey: UserDefaultsKeys.hotkeyModifiers)
        return UInt32(raw)
    }

    private var currentConfiguration: Configuration {
        Configuration(keyCode: currentKeyCode, modifiers: currentModifiers)
    }

    var currentShortcutDisplay: String {
        guard currentKeyCode >= 0 else { return L10n["onboarding.shortcut.not_set"] }
        return shortcutDisplayString(
            keyCode: Int(currentKeyCode),
            modifiers: Int(currentModifiers)
        )
    }

    func matchesCurrentShortcut(_ event: NSEvent) -> Bool {
        let eventModifiers = nseventModifiersToCarbon(
            event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
        return Self.matchesConfiguredShortcut(
            keyCode: Int(event.keyCode),
            modifiers: eventModifiers,
            configuredKeyCode: currentKeyCode,
            configuredModifiers: currentModifiers
        )
    }

    static func matchesConfiguredShortcut(
        keyCode: Int,
        modifiers: UInt32,
        configuredKeyCode: Int32,
        configuredModifiers: UInt32
    ) -> Bool {
        guard configuredKeyCode >= 0 else { return false }
        return keyCode == Int(configuredKeyCode) && modifiers == configuredModifiers
    }

    private init() {
        // 监听 UserDefaults 变化，快捷键改变后自动重注册
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func defaultsDidChange() {
        // UserDefaults.didChangeNotification 在发起变更的线程投递；后台线程写偏好会与主线程的
        // unregister()（快捷键录制中）并发操作同一组 Carbon 句柄，统一收敛到主线程。
        DispatchQueue.main.async { [weak self] in
            self?.reregister()
        }
    }

    // MARK: - 注册

    func register() {
        guard hotKeyRef == nil else { return }

        register(configuration: currentConfiguration)
    }

    private func register(configuration: Configuration) {
        lastAppliedConfiguration = configuration
        let code = configuration.keyCode

        // 禁用状态 — 不注册任何热键
        guard code >= 0 else {
            log.info("全局快捷键未配置，跳过注册", event: "hotkey.registration.skipped")
            return
        }

        let mods = configuration.modifiers

        // 1. 注册热键
        let hotKeyID = EventHotKeyID(signature: 0x434C50, id: 1) // "CLP"
        let status = RegisterEventHotKey(
            UInt32(code),
            mods,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            log.error(
                "全局快捷键注册失败",
                event: "hotkey.registration.failed",
                metadata: [
                    "status": String(status),
                    "key_code": String(code),
                    "modifiers": String(mods)
                ]
            )
            return
        }

        // 2. 安装事件处理器
        let eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: OSType(kEventHotKeyPressed))
        ]

        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotkeyHandler,
            1,
            eventSpec,
            nil,
            &eventHandler
        )

        let display = shortcutDisplayString(keyCode: Int(code), modifiers: Int(mods))
        log.info(
            "全局快捷键已注册",
            event: "hotkey.registration.succeeded",
            metadata: ["shortcut": display]
        )
    }

    func unregister() {
        let wasRegistered = hotKeyRef != nil || eventHandler != nil
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        if wasRegistered {
            log.info("全局快捷键已注销", event: "hotkey.unregistered")
        }
    }

    /// 先注销再注册 — 快捷键配置变更时调用
    func reregister(force: Bool = false) {
        let configuration = currentConfiguration
        guard force || Self.needsConfigurationUpdate(
            applied: lastAppliedConfiguration,
            current: configuration
        ) else {
            return
        }
        unregister()
        register(configuration: configuration)
    }

    static func needsConfigurationUpdate(
        applied: Configuration?,
        current: Configuration
    ) -> Bool {
        applied != current
    }

    // MARK: - 回调

    private let hotkeyHandler: EventHandlerProcPtr = { _, _, _ -> OSStatus in
        OverlayPanelManager.hotkeyFiredAt = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async {
            if AppDelegate.shared?.acknowledgeOnboardingActivation(source: .shortcut) == true {
                return
            }
            OverlayPanelManager.shared.toggle()
        }
        return noErr
    }
}
