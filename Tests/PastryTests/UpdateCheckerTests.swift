import XCTest
@testable import Pastry
import Foundation

// MARK: - UpdateChecker 测试套件

final class UpdateCheckerTests: XCTestCase {

    func testCheckOutcomeDistinguishesSuccessSkipAndFailure() {
        let outcomes: [UpdateChecker.CheckOutcome] = [.upToDate, .skipped, .failed]
        XCTAssertEqual(outcomes.count, 3)

        if case .failed = outcomes[2] {
            // 失败必须是独立状态，不能与“已是最新版本”共用 nil。
        } else {
            XCTFail("检查失败应保留独立状态")
        }
    }
    private var networkTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["PASTRY_NETWORK_TESTS"] == "1"
    }

    private func requireNetworkTestsEnabled() throws {
        guard networkTestsEnabled else {
            throw XCTSkip("Set PASTRY_NETWORK_TESTS=1 to run network-dependent updater tests")
        }
    }

    private final class ProgressRecorder: @unchecked Sendable {
        private var values: [Double] = []
        private let lock = NSLock()

        func append(_ value: Double) {
            lock.withLock { values.append(value) }
        }

        var snapshot: [Double] {
            lock.withLock { values }
        }
    }

    // MARK: - downloadBinary 进度回调

    /// onProgress 在下载过程中被调用，提供 0.0~1.0 范围内的进度值
    func testDownloadBinaryProgressCallback() async throws {
        try requireNetworkTestsEnabled()

        let checker = UpdateChecker.shared

        guard let result = await checker.checkForUpdate(force: true) else {
            throw XCTSkip("无可用更新或网络不可达，跳过下载测试")
        }

        let progress = ProgressRecorder()

        let url = try await checker.downloadBinary(
            from: result.downloadURL,
            expectedSize: result.downloadSize,
            onProgress: { value in
                progress.append(value)
            }
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let values = progress.snapshot

        XCTAssertFalse(values.isEmpty, "下载应至少发出开始和完成进度")
        if let last = values.last {
            XCTAssertEqual(last, 1.0, accuracy: 0.01, "最终进度应接近 1.0")
        }
        if let first = values.first {
            XCTAssertGreaterThanOrEqual(first, 0.0, "起始进度应 ≥ 0")
        }

        try? FileManager.default.removeItem(at: url)
    }

    /// onProgress 为 nil 时不应崩溃
    func testDownloadBinaryNilProgress() async throws {
        try requireNetworkTestsEnabled()

        let checker = UpdateChecker.shared

        guard let result = await checker.checkForUpdate(force: true) else {
            throw XCTSkip("无可用更新或网络不可达，跳过下载测试")
        }

        let url = try await checker.downloadBinary(from: result.downloadURL, expectedSize: result.downloadSize, onProgress: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
    }

    func testDownloadBinaryRejectsInsecureURL() async {
        do {
            _ = try await UpdateChecker.shared.downloadBinary(from: "http://example.com/Pastry.dmg", expectedSize: 0)
            XCTFail("HTTP 下载链接应被拒绝")
        } catch let error as UpdateChecker.UpdateError {
            XCTAssertEqual(error, .insecureURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDownloadProgressUsesResponseContentLength() throws {
        let progress = UpdateChecker.downloadProgressForTesting(
            totalBytesWritten: 250,
            totalBytesExpectedToWrite: 1_000,
            expectedSize: 2_000
        )
        XCTAssertEqual(try XCTUnwrap(progress), 0.25, accuracy: 0.001)
    }

    func testDownloadProgressFallsBackToReleaseAssetSize() throws {
        let progress = UpdateChecker.downloadProgressForTesting(
            totalBytesWritten: 250,
            totalBytesExpectedToWrite: -1,
            expectedSize: 1_000
        )
        XCTAssertEqual(try XCTUnwrap(progress), 0.25, accuracy: 0.001)
    }

    func testDownloadProgressCapsBeforeCompletion() throws {
        let progress = UpdateChecker.downloadProgressForTesting(
            totalBytesWritten: 1_500,
            totalBytesExpectedToWrite: -1,
            expectedSize: 1_000
        )
        XCTAssertEqual(try XCTUnwrap(progress), 0.99, accuracy: 0.001)
    }

    func testDownloadByteLimitAllowsSlackAboveExpectedSize() {
        let limit = UpdateChecker.downloadByteLimitForTesting(expectedSize: 10_000_000)

        XCTAssertGreaterThan(limit, 10_000_000)
        XCTAssertLessThanOrEqual(limit, 13_000_000)
    }

    func testDownloadByteLimitCapsUnknownSize() {
        XCTAssertEqual(
            UpdateChecker.downloadByteLimitForTesting(expectedSize: 0),
            300 * 1024 * 1024
        )
    }

    // MARK: - isDevBuild

    func testIsDevBuildDetection() {
        let checker = UpdateChecker.shared
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let isDev = version.contains("-dev")
        XCTAssertEqual(checker.isDevBuild, isDev)
    }

    func testDisplayVersionStripsLeadingV() {
        XCTAssertEqual(UpdateChecker.displayVersion("v1.2.3"), "1.2.3")
        XCTAssertEqual(UpdateChecker.displayVersion("vv1.2.3"), "1.2.3")
        XCTAssertEqual(UpdateChecker.displayVersion("1.2.3"), "1.2.3")
    }

    func testVersionComparisonHandlesLeadingVAndDifferentLengths() {
        XCTAssertTrue(UpdateChecker.isNewer(tag: "v1.10.0", than: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer(tag: "vv2.0", than: "v1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer(tag: "v1.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer(tag: "1.2.3", than: "v1.2.4"))
    }

    func testVersionComparisonIgnoresDevBuildSuffix() {
        XCTAssertFalse(UpdateChecker.isNewer(tag: "v1.4.2", than: "1.4.2-dev+abc123"))
        XCTAssertTrue(UpdateChecker.isNewer(tag: "v1.4.3", than: "1.4.2-dev+abc123"))
    }

    func testReleaseNotesNormalizeRecentReleases() {
        let releases = [
            UpdateChecker.ReleaseInfo(
                tag_name: "v1.4.2",
                html_url: "https://example.com/v1.4.2",
                body: "- 新增更新页历史记录",
                published_at: "2026-06-19T00:00:00Z",
                assets: []
            ),
            UpdateChecker.ReleaseInfo(
                tag_name: "v1.4.1",
                html_url: "https://example.com/v1.4.1",
                body: nil,
                published_at: "2026-06-18T00:00:00Z",
                assets: []
            )
        ]

        let notes = UpdateChecker.releaseNotes(from: releases)

        XCTAssertEqual(notes.map(\.version), ["1.4.2", "1.4.1"])
        XCTAssertEqual(notes.first?.body, "- 新增更新页历史记录")
        XCTAssertEqual(notes.last?.body, "")
        XCTAssertEqual(notes.first?.htmlURL, "https://example.com/v1.4.2")
    }

    func testUpdateInstallScriptUsesBackupReplaceWithoutResigning() {
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: "/tmp/pastry_update.dmg",
            targetPath: "/Applications/Pastry.app",
            expectedVersion: "1.3.18"
        )

        XCTAssertTrue(script.contains("BACKUP=\"$TARGET_PARENT/.${TARGET_NAME}.update-backup-$(date +%s)\""))
        XCTAssertTrue(script.contains("LOG=\"/tmp/pastry_update.log\""))
        XCTAssertTrue(script.contains("ERROR_FILE=\"/tmp/pastry_update_error.txt\""))
        XCTAssertTrue(script.contains(#"printf "%s\n" "$1" > "$ERROR_FILE""#))
        XCTAssertTrue(script.contains("exec >> \"$LOG\" 2>&1"))
        XCTAssertTrue(script.contains("mv \"$TARGET\" \"$BACKUP\""))
        XCTAssertTrue(script.contains("mv \"$BACKUP\" \"$TARGET\""))
        XCTAssertFalse(script.contains("codesign --force --deep --sign"))
        XCTAssertFalse(script.contains("更新包签名身份与当前 App 不匹配\" >&2\n            hdiutil detach"))
    }

    func testUpdateInstallScriptVerifiesExpectedVersion() {
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: "/tmp/pastry_update.dmg",
            targetPath: "/Applications/Pastry.app",
            expectedVersion: "1.3.18"
        )

        XCTAssertTrue(script.contains("EXPECTED_VERSION=\"1.3.18\""))
        XCTAssertTrue(script.contains("CANDIDATE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString'"))
        XCTAssertTrue(script.contains("INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString'"))
        XCTAssertTrue(script.contains("更新包版本不匹配"))
        XCTAssertTrue(script.contains("安装后版本仍为"))
    }

    func testUpdateInstallScriptRejectsSignatureMismatchAndAdhoc() {
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: "/tmp/pastry_update.dmg",
            targetPath: "/Applications/Pastry.app",
            expectedVersion: "1.3.20"
        )

        XCTAssertTrue(script.contains("Signature=adhoc"))
        XCTAssertTrue(script.contains("更新包使用 ad-hoc 签名，拒绝自动更新"))
        XCTAssertTrue(script.contains("更新包签名身份与当前 App 不匹配，拒绝自动更新"))
        XCTAssertTrue(script.contains("fail_update \"更新包签名身份与当前 App 不匹配，拒绝自动更新\""))
        XCTAssertTrue(script.contains("fail_update \"更新包签名校验失败\""))
        XCTAssertTrue(script.contains("CANDIDATE_REQ=$(/usr/bin/codesign -dr - \"$CANDIDATE\""))
        XCTAssertTrue(script.contains(#"[ "$CANDIDATE_REQ" != "$CURRENT_REQ" ]"#))
        XCTAssertFalse(script.contains(#"-R="$CURRENT_REQ""#))
        XCTAssertFalse(script.contains(#"-R="designated => $CURRENT_REQ""#))

        guard let mismatchRange = script.range(of: "fail_update \"更新包签名身份与当前 App 不匹配"),
              let replaceRange = script.range(of: "# 替换整个 .app") else {
            XCTFail("Script should contain signature mismatch rejection and replacement step")
            return
        }
        let mismatchBlock = script[mismatchRange.lowerBound..<replaceRange.lowerBound]
        XCTAssertTrue(mismatchBlock.contains("fail_update"))
    }
}
