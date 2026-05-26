import XCTest
@testable import DriftlineCore

final class FileBrowserTests: XCTestCase {
    func testSorterPlacesFoldersFirstThenNames() {
        let items = [
            FileItem(name: "z.txt", path: "/z.txt", kind: .file, source: .local),
            FileItem(name: "Alpha", path: "/Alpha", kind: .folder, source: .local),
            FileItem(name: "a.txt", path: "/a.txt", kind: .file, source: .local)
        ]

        let sorted = FileItemSorter.sort(items, preferences: FileListPreferences())

        XCTAssertEqual(sorted.map(\.name), ["Alpha", "a.txt", "z.txt"])
    }

    func testLocalFileListingHidesDotFilesByDefault() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(atPath: root.appendingPathComponent(".secret").path, contents: Data())
        FileManager.default.createFile(atPath: root.appendingPathComponent("visible.txt").path, contents: Data())

        let client = FoundationLocalFileSystemClient()
        let items = try await client.listDirectory(at: root.path, preferences: FileListPreferences())

        XCTAssertEqual(items.map(\.name), ["visible.txt"])
    }
}
