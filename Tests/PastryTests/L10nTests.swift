import XCTest
@testable import Pastry

// MARK: - L10n 本地化测试套件

final class L10nTests: XCTestCase {

    // MARK: - 菜单栏文案键值存在

    /// 菜单栏所有键在 catalog 中都有中英文翻译
    func testMenuBarKeysExist() {
        let keys = [
            "menu.open_clipboard",
            "menu.about", "menu.settings", "menu.quit",
            "menu.check_updates", "menu.onboarding", "menu.status_tooltip"
        ]
        for key in keys {
            let value = L10n[key]
            XCTAssertNotEqual(value, key,
                              "\(key) 应有翻译，不应返回 key 本身")
        }
    }

    func testOnboardingKeysExist() {
        let keys = [
            "onboarding.window_title", "onboarding.later", "onboarding.back",
            "onboarding.skip_step", "onboarding.start", "onboarding.continue",
            "onboarding.finish_open",
            "onboarding.welcome.title", "onboarding.welcome.subtitle",
            "onboarding.welcome.local_title", "onboarding.welcome.local_subtitle",
            "onboarding.welcome.excluded_title", "onboarding.welcome.excluded_subtitle",
            "onboarding.welcome.menubar_title", "onboarding.welcome.menubar_subtitle",
            "onboarding.shortcut.title", "onboarding.shortcut.subtitle",
            "onboarding.shortcut.detected_title", "onboarding.shortcut.detected_subtitle",
            "onboarding.shortcut.menubar_detected_title",
            "onboarding.shortcut.menubar_detected_subtitle",
            "onboarding.shortcut.menubar_hint", "onboarding.shortcut.not_set",
            "onboarding.copy.title", "onboarding.copy.subtitle",
            "onboarding.copy.detected_title", "onboarding.copy.detected_subtitle",
            "onboarding.copy.sample_text", "onboarding.copy.action",
            "onboarding.copy.copied_action",
            "onboarding.copy.anywhere_hint",
            "onboarding.permission.title", "onboarding.permission.subtitle",
            "onboarding.permission.optional_hint"
        ]
        for key in keys {
            XCTAssertNotEqual(L10n[key], key, "\(key) 应有翻译")
        }
    }

    /// 右键卡片菜单所有键存在
    func testContextMenuKeysExist() {
        let keys = [
            "context.pin", "context.unpin",
            "context.open", "context.open_with", "context.open_with_other",
            "context.preview", "context.share", "context.delete",
            "context.show_in_finder"
        ]
        for key in keys {
            let value = L10n[key]
            XCTAssertNotEqual(value, key,
                              "\(key) 应有翻译，不应返回 key 本身")
        }
    }

    /// 历史保留设置所有键存在
    func testHistoryRetentionSettingsKeysExist() {
        let keys = [
            "settings.history.section",
            "settings.history.max_items",
            "settings.history.max_age",
            "settings.history.retention_hint",
            "settings.history.max_items_value",
            "settings.history.age_never",
            "settings.history.age_days",
            "settings.history.age_one_year",
            "settings.history.age_metric_never",
            "settings.history.age_metric_days",
            "settings.history.age_metric_one_year",
            "settings.general.subtitle",
            "settings.sidebar.subtitle",
            "settings.sidebar.footer",
            "settings.tab.version",
            "settings.shortcut.subtitle",
            "shortcut.section_title",
            "shortcut.overlay_shortcut",
            "shortcut.applies_immediately",
            "shortcut.clear_shortcut",
            "shortcut.clear_hint",
            "shortcut.clear_button",
            "shortcut.record_button",
            "settings.general.metric_current_items",
            "settings.general.metric_favorites",
            "settings.general.metric_sources",
            "settings.general.section_application",
            "settings.general.language_help",
            "settings.general.launch_help",
            "settings.general.launch_failed",
            "settings.general.sound_help",
            "settings.card_click_mode",
            "settings.card_click_mode.help",
            "settings.card_click_mode.speed",
            "settings.card_click_mode.select_first",
            "settings.delete_requires_confirmation",
            "settings.delete_requires_confirmation.help",
            "settings.advanced",
            "settings.general.maximum_history",
            "settings.general.max_items_help",
            "settings.general.keep_records_for",
            "settings.general.keep_records_help",
            "settings.general.clear_all_help",
            "settings.version.subtitle",
            "settings.version.up_to_date",
            "settings.version.current_build",
            "settings.version.check_again",
            "settings.version.recent_changes",
            "settings.version.no_release_notes",
            "update.check_failed_hint",
            "settings.version.available_badge",
            "settings.tab.about",
            "settings.about.subtitle",
            "settings.about.section_product",
            "settings.about.section_resources",
            "settings.about.created_by",
            "settings.about.copyright",
            "settings.about.source_code",
            "settings.about.source_code_help",
            "settings.about.open",
            "settings.about.license",
            "settings.about.license_help",
            "about.description",
            "about.copyright",
            "settings.security.subtitle",
            "settings.security.privacy",
            "settings.diagnostics_section",
            "settings.performance_logging",
            "settings.performance_logging_hint",
            "settings.developer_diagnostics",
            "settings.developer_diagnostics_hint",
            "settings.excluded_remove",
            "search.accessibility_label",
            "search.clear",
            "card.selected",
            "card.link_preview_enable_hint",
            "delete.confirm_title",
            "delete.confirm_msg",
            "delete.confirm_msg_with_favorites",
            "delete.confirm_cancel",
            "delete.confirm_ok",
            "empty.no_pins_hint",
            "empty.no_results_hint",
            "empty.no_history_hint",
            "empty.copy_try_hint",
            "overlay.accessibility_banner",
            "overlay.accessibility_banner_action",
            "time.minute_ago", "time.minutes_ago",
            "time.hour_ago", "time.hours_ago",
            "time.day_ago", "time.days_ago"
        ]
        for key in keys {
            let value = L10n[key]
            XCTAssertNotEqual(value, key,
                              "\(key) 应有翻译，不应返回 key 本身")
        }
    }

    // MARK: - 语言切换

    /// 切换到英文后返回英文翻译
    func testSwitchToEnglish() {
        let saved = UserDefaults.standard.string(forKey: UserDefaultsKeys.language)
        UserDefaults.standard.set("en", forKey: UserDefaultsKeys.language)
        // 强制重新加载 catalog
        L10n.reloadCatalogForTesting()

        let value = L10n["menu.open_clipboard"]
        XCTAssertEqual(value, "Open Panel")

        if let saved = saved {
            UserDefaults.standard.set(saved, forKey: UserDefaultsKeys.language)
        } else {
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.language)
        }
        L10n.reloadCatalogForTesting()
    }

    /// 切换到中文后返回中文翻译
    func testSwitchToChinese() {
        let saved = UserDefaults.standard.string(forKey: UserDefaultsKeys.language)
        UserDefaults.standard.set("zh-Hans", forKey: UserDefaultsKeys.language)
        L10n.reloadCatalogForTesting()

        let value = L10n["menu.open_clipboard"]
        XCTAssertEqual(value, "打开面板")

        if let saved = saved {
            UserDefaults.standard.set(saved, forKey: UserDefaultsKeys.language)
        } else {
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.language)
        }
        L10n.reloadCatalogForTesting()
    }

    // MARK: - Fallback

    /// 不存在的 key 返回 key 本身
    func testMissingKeyReturnsSelf() {
        let value = L10n["this.key.does.not.exist"]
        XCTAssertEqual(value, "this.key.does.not.exist")
    }
}
