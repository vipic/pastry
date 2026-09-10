import Foundation
import XCTest

final class SigningConfigurationTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(of relativePath: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testScriptsDefaultToSharedAuthorSigningIdentity() throws {
        let deployScript = try contents(of: "deploy.sh")
        let releaseScript = try contents(of: "release.sh")

        XCTAssertTrue(deployScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Nekutai}""#))
        XCTAssertTrue(releaseScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Nekutai}""#))
        XCTAssertFalse(deployScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Pastry Dev}""#))
        XCTAssertFalse(releaseScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Pastry Release}""#))
    }

    func testScriptsRejectAdhocSigningFallback() throws {
        let deployScript = try contents(of: "deploy.sh")
        let releaseScript = try contents(of: "release.sh")

        for script in [deployScript, releaseScript] {
            XCTAssertTrue(script.contains("不能使用 ad-hoc 签名"))
            XCTAssertFalse(script.contains("回退 ad-hoc"))
            XCTAssertFalse(script.contains("codesign --force --sign -"))
            XCTAssertFalse(script.contains("codesign --force --deep --sign -"))
        }
    }

    func testInfoPlistOptsOutOfDefaultOneTimeCodeAutofill() throws {
        let deployScript = try contents(of: "deploy.sh")
        let releaseScript = try contents(of: "release.sh")

        XCTAssertTrue(deployScript.contains("NSAutoFillRequiresTextContentTypeForOneTimeCodeOnMac"))
        XCTAssertTrue(releaseScript.contains("NSAutoFillRequiresTextContentTypeForOneTimeCodeOnMac"))
    }

}
