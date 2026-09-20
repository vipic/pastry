import AppKit
import XCTest
@testable import Pastry

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

    func testTrayPlacementPreferencesAndCardAxis() {
        XCTAssertEqual(UserDefaultsKeys.trayPlacementMode, "tray_placement_mode")
        XCTAssertEqual(UserDefaultsKeys.trayRememberedPlacement, "tray_remembered_placement")
        XCTAssertEqual(TrayPlacementMode.resolved(stored: nil), .fixedBottom)
        XCTAssertEqual(TrayPlacementMode.resolved(stored: "unknown"), .fixedBottom)

        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }

        TrayPlacementPreferences.remember(.right, defaults: defaults)
        defaults.set(TrayPlacementMode.fixedBottom.rawValue, forKey: UserDefaultsKeys.trayPlacementMode)
        XCTAssertEqual(TrayPlacementPreferences.effectivePlacement(defaults: defaults), .bottom)

        defaults.set(TrayPlacementMode.followMemory.rawValue, forKey: UserDefaultsKeys.trayPlacementMode)
        XCTAssertEqual(TrayPlacementPreferences.effectivePlacement(defaults: defaults), .right)

        XCTAssertTrue(TrayPlacement.bottom.usesHorizontalCards(screenWidth: 1_440))
        XCTAssertFalse(TrayPlacement.bottom.usesHorizontalCards(screenWidth: 1_200))
        XCTAssertFalse(TrayPlacement.left.usesHorizontalCards(screenWidth: 1_440))
        XCTAssertFalse(TrayPlacement.right.usesHorizontalCards(screenWidth: 1_440))
    }

    func testTrayPlacementMigratesLegacySidePreferenceToFollowMemory() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set("left", forKey: "tray_placement")

        TrayPlacementPreferences.migrateLegacyPreference(defaults: defaults)

        XCTAssertEqual(TrayPlacementPreferences.mode(defaults: defaults), .followMemory)
        XCTAssertEqual(TrayPlacementPreferences.rememberedPlacement(defaults: defaults), .left)
        XCTAssertNil(defaults.object(forKey: "tray_placement"))
    }

    func testTrayPanelFramesAndEdgeDockingRegions() {
        let screen = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        XCTAssertEqual(TrayPanelLayout.panelFrame(for: .bottom, in: screen), NSRect(x: 0, y: 0, width: 1_440, height: 336))
        XCTAssertEqual(TrayPanelLayout.panelFrame(for: .left, in: screen), NSRect(x: 0, y: 0, width: 344, height: 900))
        XCTAssertEqual(TrayPanelLayout.panelFrame(for: .right, in: screen), NSRect(x: 1_096, y: 0, width: 344, height: 900))
        XCTAssertEqual(
            TrayPanelLayout.panelFrame(for: .left, in: screen, compactSideTray: true),
            NSRect(x: 0, y: 0, width: 296, height: 900)
        )
        XCTAssertEqual(
            TrayPanelLayout.panelFrame(for: .right, in: screen, compactSideTray: true),
            NSRect(x: 1_144, y: 0, width: 296, height: 900)
        )
        XCTAssertEqual(TrayPanelLayout.dockingPlacement(at: NSPoint(x: 300, y: 450), in: screen), .left)
        XCTAssertEqual(TrayPanelLayout.dockingPlacement(at: NSPoint(x: 1_140, y: 450), in: screen), .right)
        XCTAssertEqual(TrayPanelLayout.dockingPlacement(at: NSPoint(x: 720, y: 300), in: screen), .bottom)
        XCTAssertNil(TrayPanelLayout.dockingPlacement(at: NSPoint(x: 400, y: 450), in: screen))
        XCTAssertEqual(TrayPanelLayout.dockingPlacement(at: NSPoint(x: 30, y: 80), in: screen), .left)
        XCTAssertEqual(TrayPanelLayout.dockingPlacement(at: NSPoint(x: 80, y: 30), in: screen), .bottom)
        XCTAssertNil(
            TrayPanelLayout.dockingPlacement(
                at: NSPoint(x: 320, y: 450),
                in: screen,
                compactSideTray: true
            )
        )
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

    func testSemanticSearchDefaultsToDisabled() {
        let key = UserDefaultsKeys.semanticSearchEnabled
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(SemanticSearchPreference.isEnabled)

        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(SemanticSearchPreference.isEnabled)
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

}
