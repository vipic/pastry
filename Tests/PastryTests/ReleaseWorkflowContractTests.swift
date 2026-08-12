import Foundation
import XCTest

final class ReleaseWorkflowContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(of relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testReleaseRequiresUnifiedValidationAndSafePublishing() throws {
        let release = try contents(of: "release.sh")
        XCTAssertTrue(release.contains("command_log_run_tail mise_check 12 mise run check"))
        XCTAssertTrue(release.contains("git push --atomic"))
        XCTAssertTrue(release.contains("gh release create"))
        XCTAssertFalse(release.contains("--clobber"))
    }

    func testCIOnlyRunsSourceValidation() throws {
        let workflow = try contents(of: ".github/workflows/release-build-verification.yml")
        XCTAssertTrue(workflow.contains("mise run check"))
        XCTAssertFalse(workflow.contains("release.sh"))
        XCTAssertFalse(workflow.contains("upload-artifact"))
    }

    func testFormalPublishRequiresExplicitVersion() throws {
        let publish = try contents(of: "scripts/tasks/publish.sh")
        XCTAssertTrue(publish.contains("正式发布必须显式"))
        XCTAssertFalse(publish.contains("next_version.sh"))
    }
}
