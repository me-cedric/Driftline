import XCTest
@testable import DriftlineCore

final class RecursiveTransferTests: XCTestCase {
    func testFolderTransferJobMarksIsFolder() {
        let job = TransferJob(
            direction: .upload,
            sourcePath: "/tmp/my-folder",
            destinationPath: "/remote/my-folder",
            isFolder: true
        )
        XCTAssertTrue(job.isFolder)
    }

    func testTransferJobDefaultIsNotFolder() {
        let job = TransferJob(
            direction: .upload,
            sourcePath: "/tmp/file.txt",
            destinationPath: "/remote/file.txt"
        )
        XCTAssertFalse(job.isFolder)
    }

    func testTransferJobWithIsFolderEncodesAndDecodesCorrectly() throws {
        let original = TransferJob(
            direction: .download,
            sourcePath: "/remote/assets",
            destinationPath: "/tmp/assets",
            byteCount: 4096,
            isFolder: true,
            status: .queued,
            serverName: "prod",
            protocolKind: .sftp
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(TransferJob.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.direction, original.direction)
        XCTAssertEqual(decoded.sourcePath, original.sourcePath)
        XCTAssertEqual(decoded.destinationPath, original.destinationPath)
        XCTAssertEqual(decoded.byteCount, original.byteCount)
        XCTAssertTrue(decoded.isFolder)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.serverName, original.serverName)
        XCTAssertEqual(decoded.protocolKind, original.protocolKind)
    }

    func testTransferJobWithIsFolderFalseRoundTrips() throws {
        let original = TransferJob(
            direction: .upload,
            sourcePath: "/tmp/report.pdf",
            destinationPath: "/remote/report.pdf",
            isFolder: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(TransferJob.self, from: encoded)

        XCTAssertFalse(decoded.isFolder)
        XCTAssertEqual(decoded.sourcePath, original.sourcePath)
    }

    func testTransferJobIsFolderAbsentInJsonDefaultsToFalse() throws {
        let baseJob = TransferJob(
            direction: .upload,
            sourcePath: "/tmp/file.txt",
            destinationPath: "/remote/file.txt",
            isFolder: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var dict = try JSONSerialization.jsonObject(with: try encoder.encode(baseJob)) as! [String: Any]
        dict.removeValue(forKey: "isFolder")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(TransferJob.self, from: legacyData)

        XCTAssertFalse(decoded.isFolder)
    }
}
