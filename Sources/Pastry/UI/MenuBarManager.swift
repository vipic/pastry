import Cocoa
import SwiftUI
import OSLog

enum MenuBarClickAction: Equatable {
    case showMenu
    case acknowledgeOnboarding
    case toggleOverlay
}

// MARK: - 菜单栏管理器（左键打开面板，右键弹出菜单）
final class MenuBarManager: NSObject {

    nonisolated(unsafe) static let shared = MenuBarManager()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "menubar")

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private override init() {
        super.init()
    }

    @MainActor
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        buildMenu()

        if let button = statusItem.button {
            button.image = menuBarIcon()
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = L10n["menu.status_tooltip"]
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .pastryLanguageDidChange,
            object: nil
        )

        log.info("菜单栏已配置")
    }

    // MARK: - 点击处理

    @MainActor
    @objc private func statusItemClicked() {
        let shortcutStepVisible = AppDelegate.shared?.isOnboardingShortcutStepVisible == true
        switch Self.clickAction(for: NSApp.currentEvent?.type, shortcutStepVisible: shortcutStepVisible) {
        case .showMenu:
            showMenu()
        case .acknowledgeOnboarding:
            _ = AppDelegate.shared?.acknowledgeOnboardingActivation(source: .menuBar)
        case .toggleOverlay:
            OverlayPanelManager.shared.toggle()
        }
    }

    static func clickAction(
        for eventType: NSEvent.EventType?,
        shortcutStepVisible: Bool
    ) -> MenuBarClickAction {
        if eventType == .rightMouseUp { return .showMenu }
        if shortcutStepVisible { return .acknowledgeOnboarding }
        return .toggleOverlay
    }


    // MARK: - 构建菜单

    @MainActor
    private func buildMenu() {
        let result = MenuBarMenuFactory.build(
            target: self,
            actions: MenuBarMenuActions(
                openOverlay: #selector(openOverlay),
                showOnboarding: #selector(showOnboardingAction),
                checkUpdates: #selector(checkUpdatesAction),
                openSettings: #selector(openSettingsAction),
                quit: #selector(quitApp)
            )
        )
        menu = result.menu
    }

    @MainActor
    private func showMenu() {
        OverlayPanelManager.shared.hide()
        guard let button = statusItem.button else { return }
        let previousMenu = statusItem.menu
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = previousMenu
    }

    @MainActor
    @objc private func languageDidChange() {
        buildMenu()
        statusItem.button?.toolTip = L10n["menu.status_tooltip"]
    }

    // MARK: - 操作

    private func menuBarIcon() -> NSImage? {
        let symbolName = isUpdateDevBuild ? "clipboard" : "doc.on.clipboard"
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: "Pastry")
    }

    private var isUpdateDevBuild: Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return version.contains("-dev")
    }

    @MainActor
    @objc private func showOnboardingAction() {
        OverlayPanelManager.shared.hide()
        DispatchQueue.main.async {
            AppDelegate.shared?.showOnboardingWindow()
        }
    }

    @MainActor
    @objc private func checkUpdatesAction() {
        OverlayPanelManager.shared.hide()
        DispatchQueue.main.async {
            AppDelegate.shared?.openSettingsWindow(selectedTab: .version)
        }
    }

    @MainActor
    @objc private func openOverlay() {
        OverlayPanelManager.shared.toggle()
    }

    @MainActor
    @objc private func openSettingsAction() {
        OverlayPanelManager.shared.hide()
        // 延迟一帧：等面板关闭和菜单退出 tracking mode 后再创建设置窗口
        DispatchQueue.main.async {
            AppDelegate.shared?.openSettingsWindow()
        }
    }

    @MainActor
    @objc private func quitApp() {
        OverlayPanelManager.shared.hide()
        GlobalHotkeyManager.shared.unregister()
        NSApp.terminate(nil)
    }

}
