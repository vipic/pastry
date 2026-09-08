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

    func testCIOnlyRunsSourceValidation() throws {
        let workflow = try contents(of: ".github/workflows/release-build-verification.yml")
        XCTAssertTrue(workflow.contains("mise run check"))
        XCTAssertFalse(workflow.contains("release.sh"))
        XCTAssertFalse(workflow.contains("upload-artifact"))
    }

}
