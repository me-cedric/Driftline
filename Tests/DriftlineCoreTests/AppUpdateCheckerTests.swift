@testable import DriftlineCore
import XCTest

final class AppUpdateCheckerTests: XCTestCase {
    func testVersionComparatorHandlesTagsAndPatchVersions() {
        XCTAssertTrue(VersionComparator.isVersion("v0.4.1", newerThan: "0.4.0"))
        XCTAssertTrue(VersionComparator.isVersion("1.0.0", newerThan: "0.9.9"))
        XCTAssertFalse(VersionComparator.isVersion("0.4.0", newerThan: "0.4.0"))
        XCTAssertFalse(VersionComparator.isVersion("0.4.0-beta", newerThan: "0.4.1"))
    }

    func testGitHubReleaseDecodesLatestReleasePayload() throws {
        let payload = Data("""
        {
          "tag_name": "v0.5.0",
          "name": "Driftline 0.5.0",
          "html_url": "https://github.com/me-cedric/Driftline/releases/tag/v0.5.0",
          "published_at": "2026-06-14T10:00:00Z",
          "assets": [
            {
              "name": "Driftline-0.5.0.dmg",
              "browser_download_url": "https://github.com/me-cedric/Driftline/releases/download/v0.5.0/Driftline-0.5.0.dmg"
            }
          ]
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: payload)
        let update = AppUpdate(
            latestVersion: release.tagName,
            currentVersion: "0.4.0",
            releaseURL: release.htmlURL,
            assetURL: release.assets.first?.browserDownloadURL,
            releaseName: release.name,
            publishedAt: release.publishedAt
        )

        XCTAssertEqual(update.latestVersion, "v0.5.0")
        XCTAssertTrue(update.isNewer)
        XCTAssertEqual(update.assetURL?.lastPathComponent, "Driftline-0.5.0.dmg")
    }
}
