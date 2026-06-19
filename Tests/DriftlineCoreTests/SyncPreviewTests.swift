import DriftlineCore
import XCTest

final class SyncPreviewTests: XCTestCase {
    func testSyncPreviewSeparatesMissingChangedAndMatchingItems() {
        let localItems = [
            FileItem(name: "same.txt", path: "/local/same.txt", kind: .file, size: 10, source: .local),
            FileItem(name: "changed.txt", path: "/local/changed.txt", kind: .file, size: 20, source: .local),
            FileItem(name: "local-only.txt", path: "/local/local-only.txt", kind: .file, size: 30, source: .local),
            FileItem(name: "folder", path: "/local/folder", kind: .folder, source: .local),
        ]
        let remoteItems = [
            FileItem(name: "same.txt", path: "/remote/same.txt", kind: .file, size: 10, source: .remote),
            FileItem(name: "changed.txt", path: "/remote/changed.txt", kind: .file, size: 25, source: .remote),
            FileItem(name: "remote-only.txt", path: "/remote/remote-only.txt", kind: .file, size: 40, source: .remote),
            FileItem(name: "folder", path: "/remote/folder", kind: .folder, source: .remote),
        ]

        let preview = SyncPreview(localPath: "/local", remotePath: "/remote", localItems: localItems, remoteItems: remoteItems)

        XCTAssertEqual(preview.matchingCount, 2)
        XCTAssertEqual(preview.localOnly.map(\.name), ["local-only.txt"])
        XCTAssertEqual(preview.remoteOnly.map(\.name), ["remote-only.txt"])
        XCTAssertEqual(preview.changed.map(\.name), ["changed.txt"])
        XCTAssertEqual(preview.changed.first?.reason, "Size differs: local 20 bytes, remote 25 bytes, delta -5 bytes")
    }
}
