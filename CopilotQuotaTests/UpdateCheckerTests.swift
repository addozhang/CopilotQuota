import XCTest

final class UpdateCheckerTests: XCTestCase {
    func testSemanticVersionComparison() throws {
        XCTAssertLessThan(try XCTUnwrap(SemanticVersion("1.3.0")), try XCTUnwrap(SemanticVersion("1.4.0")))
        XCTAssertLessThan(try XCTUnwrap(SemanticVersion("v1.9.0")), try XCTUnwrap(SemanticVersion("v1.10.0")))
        XCTAssertLessThan(try XCTUnwrap(SemanticVersion("1.4.0-beta.1")), try XCTUnwrap(SemanticVersion("1.4.0")))
        XCTAssertEqual(try XCTUnwrap(SemanticVersion("v1.3")), try XCTUnwrap(SemanticVersion("1.3.0")))
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("abc"))
    }

    func testEvaluatePrefersDMGAssetWhenNewer() {
        let dmgURL = URL(string: "https://github.com/addozhang/CopilotQuota/releases/download/v1.4.0/CopilotQuota-1.4.0.dmg")!
        let zipURL = URL(string: "https://github.com/addozhang/CopilotQuota/releases/download/v1.4.0/CopilotQuota-1.4.0.zip")!
        let htmlURL = URL(string: "https://github.com/addozhang/CopilotQuota/releases/tag/v1.4.0")!

        let release = GitHubRelease(
            tagName: "v1.4.0",
            htmlURL: htmlURL,
            draft: false,
            prerelease: false,
            assets: [
                .init(name: "CopilotQuota-1.4.0.zip", browserDownloadURL: zipURL),
                .init(name: "CopilotQuota-1.4.0.dmg", browserDownloadURL: dmgURL),
            ]
        )

        let info = UpdateChecker.evaluate(release: release, currentVersion: "1.3.0")
        XCTAssertEqual(info?.version, "1.4.0")
        XCTAssertEqual(info?.downloadURL, dmgURL)
        XCTAssertEqual(info?.releaseURL, htmlURL)
    }

    func testEvaluateIgnoresSameOlderDraftOrPrerelease() {
        let htmlURL = URL(string: "https://github.com/addozhang/CopilotQuota/releases/tag/v1.4.0")!

        let same = GitHubRelease(tagName: "v1.3.0", htmlURL: htmlURL, draft: false, prerelease: false, assets: nil)
        XCTAssertNil(UpdateChecker.evaluate(release: same, currentVersion: "1.3.0"))

        let draft = GitHubRelease(tagName: "v2.0.0", htmlURL: htmlURL, draft: true, prerelease: false, assets: nil)
        XCTAssertNil(UpdateChecker.evaluate(release: draft, currentVersion: "1.3.0"))

        let pre = GitHubRelease(tagName: "v2.0.0-rc.1", htmlURL: htmlURL, draft: false, prerelease: true, assets: nil)
        XCTAssertNil(UpdateChecker.evaluate(release: pre, currentVersion: "1.3.0"))
    }
}
