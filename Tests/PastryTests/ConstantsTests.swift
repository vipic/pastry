import XCTest
@testable import Pastry
import SwiftUI

// MARK: - Constants 测试套件
// 验证常量定义的一致性

final class ConstantsTests: XCTestCase {

    // MARK: - UserDefaults Keys

    func testHotkeyKeyCodeKeyUsedInManager() {
        // GlobalHotkeyManager 读取 key 一致
        XCTAssertEqual(UserDefaultsKeys.hotkeyKeyCode, "hotkey_keycode")
    }

    func testHotkeyModifiersKeyUsedInManager() {
        XCTAssertEqual(UserDefaultsKeys.hotkeyModifiers, "hotkey_modifiers")
    }

    func testLaunchAtLoginKey() {
        XCTAssertEqual(UserDefaultsKeys.launchAtLogin, "launch_at_login")
    }

    func testSoundEnabledKey() {
        XCTAssertEqual(UserDefaultsKeys.soundEnabled, "sound_enabled")
        XCTAssertEqual(UserDefaultsKeys.cardClickMode, "card_click_mode")
        XCTAssertEqual(UserDefaultsKeys.deleteRequiresConfirmation, "delete_requires_confirmation")
    }

    func testDeleteRequiresConfirmationDefaultsToTrueWhenUnset() {
        let key = UserDefaultsKeys.deleteRequiresConfirmation
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(DeleteConfirmationPreference.requiresConfirmation)

        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(DeleteConfirmationPreference.requiresConfirmation)

        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(DeleteConfirmationPreference.requiresConfirmation)
    }

    func testSoundFeedbackEnabledReflectsUserPreference() {
        let saved = UserDefaults.standard.object(forKey: UserDefaultsKeys.soundEnabled)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: UserDefaultsKeys.soundEnabled)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.soundEnabled)
            }
        }

        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.soundEnabled)
        XCTAssertFalse(SoundFeedback.isEnabled)

        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.soundEnabled)
        XCTAssertTrue(SoundFeedback.isEnabled)
    }

    func testLinkPreviewNetworkEnabledKey() {
        XCTAssertEqual(UserDefaultsKeys.linkPreviewNetworkEnabled, "link_preview_network_enabled")
    }

    func testHistoryRetentionKeys() {
        XCTAssertEqual(UserDefaultsKeys.historyMaxItems, "history_max_items")
        XCTAssertEqual(UserDefaultsKeys.historyMaxAgeDays, "history_max_age_days")
    }

    func testPerformanceLoggingKey() {
        XCTAssertEqual(UserDefaultsKeys.performanceLoggingEnabled, "performance_logging_enabled")
    }

    func testSettingsAccessibilityIdentifiers() {
        XCTAssertEqual(AccessibilityIdentifiers.Settings.performanceLoggingToggle, "settings.performance-logging-toggle")
        XCTAssertEqual(AccessibilityIdentifiers.Settings.maxItemsPicker, "settings.max-items-picker")
        XCTAssertEqual(AccessibilityIdentifiers.Settings.maxAgePicker, "settings.max-age-picker")
    }

    func testHistoryRetentionPolicySanitizesValues() {
        XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxItems(500), 500)
        XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxItems(-1), HistoryRetentionPolicy.defaultMaxItems)
        XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxItems(0), HistoryRetentionPolicy.defaultMaxItems)
        XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxItems(9999), HistoryRetentionPolicy.defaultMaxItems)
        XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxAgeDays(30), 30)
        XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxAgeDays(13), HistoryRetentionPolicy.defaultMaxAgeDays)
        XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxAgeDays(0), 0)
        for option in HistoryRetentionPolicy.maxItemsOptions {
            XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxItems(option), option)
        }
        for option in HistoryRetentionPolicy.maxAgeDayOptions {
            XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxAgeDays(option), option)
        }
    }

    func testAppIconsAreNonEmptySFSymbolNames() {
        let names = [
            AppIcons.app, AppIcons.text, AppIcons.image, AppIcons.file,
            AppIcons.rtf, AppIcons.html, AppIcons.search, AppIcons.star,
            AppIcons.paste, AppIcons.delete, AppIcons.pin, AppIcons.settings,
            AppIcons.clear, AppIcons.quit
        ]
        for name in names {
            XCTAssertFalse(name.isEmpty)
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "SF Symbol 应存在: \(name)"
            )
        }
    }

    func testUIConstantsCardMetricsArePositive() {
        XCTAssertGreaterThan(UIConstants.Radius.card, 0)
        XCTAssertGreaterThan(UIConstants.Card.contentVerticalPadding, 0)
        XCTAssertGreaterThan(UIConstants.Overlay.cardSpacing, 0)
        XCTAssertEqual(UIConstants.Stroke.emphasis, 1.5, accuracy: 0.001)
    }

    func testHistoryRetentionMetricLabelOmitsActionPrefix() {
        let saved = UserDefaults.standard.string(forKey: UserDefaultsKeys.language)
        UserDefaults.standard.set("en", forKey: UserDefaultsKeys.language)
        L10n.reloadCatalogForTesting()

        XCTAssertEqual(HistoryRetentionPolicy.maxAgeLabel(90), "Keep for 90 days")
        XCTAssertEqual(HistoryRetentionPolicy.maxAgeMetricLabel(90), "90 days")
        XCTAssertEqual(HistoryRetentionPolicy.maxAgeMetricLabel(365), "1 year")
        XCTAssertEqual(HistoryRetentionPolicy.maxAgeMetricLabel(0), "No limit")

        if let saved {
            UserDefaults.standard.set(saved, forKey: UserDefaultsKeys.language)
        } else {
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.language)
        }
        L10n.reloadCatalogForTesting()
    }

    // MARK: - AppName

    func testAppName() {
        #if DEBUG
        XCTAssertEqual(Constants.appName, "Pastry Dev")
        #else
        XCTAssertEqual(Constants.appName, "Pastry")
        #endif
    }

    // MARK: - Colors

    func testClipBackgroundColor() {
        let color = Color.clipBackground
        // NSColor → Color 可双向转换
        let nsColor = NSColor(color)
        XCTAssertNotNil(nsColor.usingColorSpace(.sRGB))
    }

    func testClipRowHoverColor() {
        let color = Color.clipRowHover
        let nsColor = NSColor(color)
        XCTAssertNotNil(nsColor.usingColorSpace(.sRGB))
    }

    func testClipAccentColor() {
        let color = Color.clipAccent
        let nsColor = NSColor(color)
        XCTAssertNotNil(nsColor.usingColorSpace(.sRGB))
    }

    func testUICardConstantsAreStable() {
        XCTAssertEqual(UIConstants.Card.size, 240)
        XCTAssertEqual(UIConstants.Radius.card, 10)
        XCTAssertEqual(UIConstants.Card.contentVerticalPadding, 6)
        XCTAssertEqual(UIConstants.Card.footerBottomPadding, 8)
    }

    func testUIOverlayConstantsAreStable() {
        XCTAssertEqual(UIConstants.Overlay.cardSpacing, 10)
        XCTAssertEqual(UIConstants.Overlay.accentFillOpacity, 0.12, accuracy: 0.001)
        XCTAssertEqual(UIConstants.Overlay.overlaySurfaceTintOpacity, 0.55, accuracy: 0.001)
    }

    // MARK: - SF Symbols

    func testAppIconSymbolNotEmpty() {
        XCTAssertFalse(AppIcons.app.isEmpty)
    }

    func testSearchSymbolNotEmpty() {
        XCTAssertFalse(AppIcons.search.isEmpty)
    }

    func testStarSymbolsNotEmpty() {
        XCTAssertFalse(AppIcons.star.isEmpty)
        XCTAssertFalse(AppIcons.starEmpty.isEmpty)
    }

    func testSettingsSymbolNotEmpty() {
        XCTAssertFalse(AppIcons.settings.isEmpty)
    }

    func testPinSymbolNotEmpty() {
        XCTAssertFalse(AppIcons.pin.isEmpty)
    }
}
