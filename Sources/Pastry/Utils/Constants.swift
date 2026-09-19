import Foundation
import SwiftUI

// MARK: - 应用常量

enum Constants {
    #if DEBUG
    static let appName = "Pastry Dev"
    #else
    static let appName = "Pastry"
    #endif
}

// MARK: - SF Symbols 封装

enum AppIcons {
    static let app = "clipboard"
    static let text = "text.alignleft"
    static let image = "photo"
    static let file = "folder"
    static let rtf = "doc.richtext"
    static let html = "chevron.left.forwardslash.chevron.right"
    static let search = "magnifyingglass"
    static let star = "star.fill"
    static let starEmpty = "star"
    static let paste = "arrow.right.doc.on.clipboard"
    static let copy = "doc.on.doc"
    static let delete = "trash"
    static let pin = "pin.fill"
    static let settings = "gearshape"
    static let clear = "clear"
    static let quit = "power"
}

// MARK: - UserDefaults Keys

enum UserDefaultsKeys {
    static let language = "PastryLanguage"
    static let launchAtLogin = "launch_at_login"
    static let soundEnabled = "sound_enabled"
    /// 卡片左键：enhanced = 单击选中 / 再点已选粘贴；speed = 单击粘贴
    static let cardClickMode = "card_click_mode"
    /// 删除历史记录前是否弹出确认（默认 true）
    static let deleteRequiresConfirmation = "delete_requires_confirmation"
    static let hotkeyKeyCode = "hotkey_keycode"
    static let hotkeyModifiers = "hotkey_modifiers"
    static let excludedBundleIDs = "excluded_bundle_ids"
    static let linkPreviewNetworkEnabled = "link_preview_network_enabled"
    static let historyMaxItems = "history_max_items"
    static let historyMaxAgeDays = "history_max_age_days"
    /// 上次完成失效文件记录清理的时间；用于把低频维护限制为每天一次。
    static let missingFileCleanupLastRun = "missing_file_cleanup_last_run"
    static let performanceLoggingEnabled = "performance_logging_enabled"
    /// 实验性的设备端智能找回。缺省关闭，确保升级后保持既有关键词搜索行为。
    static let semanticSearchEnabled = "semantic_search_enabled"
    /// 已完成的新手引导版本。使用版本号而非布尔值，便于未来只补充重大新增步骤。
    static let onboardingCompletedVersion = "onboarding_completed_version"
}

enum SemanticSearchPreference {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.semanticSearchEnabled)
    }
}

/// 删除确认偏好。缺省键时视为开启，避免 `bool(forKey:)` 对缺失键返回 false。
enum DeleteConfirmationPreference {
    static var requiresConfirmation: Bool {
        guard UserDefaults.standard.object(forKey: UserDefaultsKeys.deleteRequiresConfirmation) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: UserDefaultsKeys.deleteRequiresConfirmation)
    }
}

extension Notification.Name {
    static let pastryLanguageDidChange = Notification.Name("pastryLanguageDidChange")
    static let onboardingActivationDetected = Notification.Name("onboardingActivationDetected")
}

// MARK: - 颜色

extension Color {
    static let clipBackground = Color(nsColor: NSColor.windowBackgroundColor)
    static let clipRowHover = Color(nsColor: NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3))
    static let clipAccent = Color.accentColor
    /// Brand warm accent. Prefer `PastryPalette.warmAccent` at call sites.
    static let pastryWarmAccent = Color(red: 0.741, green: 0.463, blue: 0.184)
}

extension NSColor {
    static let pastryWarmAccent = NSColor(calibratedRed: 0.741, green: 0.463, blue: 0.184, alpha: 1)
}
