@testable import DriftlineCore
import XCTest

final class AtomicDownloadDestinationTests: XCTestCase {
    func testPrepareWritesPartialWithoutReplacingFinalFile() throws {
        let root = self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let finalURL = root.appendingPathComponent("report.txt")
        try "old".write(to: finalURL, atomically: true, encoding: .utf8)

        let destination = AtomicDownloadDestination(finalURL: finalURL, id: self.fixedID())
        let handle = try destination.prepare()
        try handle.write(contentsOf: Data("new".utf8))
        try handle.close()

        XCTAssertEqual(try String(contentsOf: finalURL, encoding: .utf8), "old")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.temporaryURL.path))

        try destination.commit()

        XCTAssertEqual(try String(contentsOf: finalURL, encoding: .utf8), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.temporaryURL.path))
    }

    func testCleanupRemovesPartialWithoutTouchingFinalFile() throws {
        let root = self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let finalURL = root.appendingPathComponent("report.txt")
        try "old".write(to: finalURL, atomically: true, encoding: .utf8)

        let destination = AtomicDownloadDestination(finalURL: finalURL, id: self.fixedID())
        let handle = try destination.prepare()
        try handle.write(contentsOf: Data("partial".utf8))
        try handle.close()

        destination.cleanup()

        XCTAssertEqual(try String(contentsOf: finalURL, encoding: .utf8), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.temporaryURL.path))
    }

    func testCommitRefusesToReplaceDirectory() throws {
        let root = self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let finalURL = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: finalURL, withIntermediateDirectories: true)

        let destination = AtomicDownloadDestination(finalURL: finalURL, id: self.fixedID())
        let handle = try destination.prepare()
        try handle.write(contentsOf: Data("new".utf8))
        try handle.close()
        defer { destination.cleanup() }

        XCTAssertThrowsError(try destination.commit())

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftlineAtomicDownloadTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func fixedID() -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    }
}
