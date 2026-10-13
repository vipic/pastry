import XCTest
@testable import Pastry
import AppKit
import Carbon

// MARK: - 快捷键工具测试套件
// 测试 NSEvent→Carbon 修饰键转换、快捷键匹配与配置更新

final class HotkeyUtilsTests: XCTestCase {

    // MARK: - nseventModifiersToCarbon

    func testCommandOnly() {
        let flags: NSEvent.ModifierFlags = .command
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(cmdKey))
    }

    func testShiftOnly() {
        let flags: NSEvent.ModifierFlags = .shift
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(shiftKey))
    }

    func testOptionOnly() {
        let flags: NSEvent.ModifierFlags = .option
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(optionKey))
    }

    func testControlOnly() {
        let flags: NSEvent.ModifierFlags = .control
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(controlKey))
    }

    func testCommandShift() {
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(cmdKey) | UInt32(shiftKey))
    }

    func testCommandOptionControl() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .control]
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey))
    }

    func testAllFourModifiers() {
        let flags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey) | UInt32(controlKey))
    }

    func testNoModifiers() {
        let flags: NSEvent.ModifierFlags = []
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, 0)
    }

    func testConfiguredShortcutMatchRequiresKeyAndModifiers() {
        let configuredModifiers = UInt32(cmdKey) | UInt32(shiftKey)

        XCTAssertTrue(GlobalHotkeyManager.matchesConfiguredShortcut(
            keyCode: 9,
            modifiers: configuredModifiers,
            configuredKeyCode: 9,
            configuredModifiers: configuredModifiers
        ))
        XCTAssertFalse(GlobalHotkeyManager.matchesConfiguredShortcut(
            keyCode: 8,
            modifiers: configuredModifiers,
            configuredKeyCode: 9,
            configuredModifiers: configuredModifiers
        ))
        XCTAssertFalse(GlobalHotkeyManager.matchesConfiguredShortcut(
            keyCode: 9,
            modifiers: UInt32(cmdKey),
            configuredKeyCode: 9,
            configuredModifiers: configuredModifiers
        ))
    }

    func testDisabledConfiguredShortcutNeverMatches() {
        XCTAssertFalse(GlobalHotkeyManager.matchesConfiguredShortcut(
            keyCode: 9,
            modifiers: UInt32(cmdKey) | UInt32(shiftKey),
            configuredKeyCode: GlobalHotkeyManager.disabledSentinel,
            configuredModifiers: UInt32(cmdKey) | UInt32(shiftKey)
        ))
    }

    func testHotkeyConfigurationOnlyUpdatesWhenValuesChange() {
        let current = GlobalHotkeyManager.Configuration(
            keyCode: 9,
            modifiers: UInt32(cmdKey) | UInt32(shiftKey)
        )

        XCTAssertTrue(GlobalHotkeyManager.needsConfigurationUpdate(
            applied: nil,
            current: current
        ))
        XCTAssertFalse(GlobalHotkeyManager.needsConfigurationUpdate(
            applied: current,
            current: current
        ))
        XCTAssertTrue(GlobalHotkeyManager.needsConfigurationUpdate(
            applied: current,
            current: .init(keyCode: 8, modifiers: current.modifiers)
        ))
        XCTAssertTrue(GlobalHotkeyManager.needsConfigurationUpdate(
            applied: current,
            current: .init(keyCode: current.keyCode, modifiers: UInt32(cmdKey))
        ))
    }

}
