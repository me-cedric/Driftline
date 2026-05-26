import XCTest
@testable import DriftlineCore

final class StatsTests: XCTestCase {
    func testTransferStatsCalculatorSummarizesJobs() {
        let jobs = [
            TransferJob(direction: .upload, sourcePath: "/a", destinationPath: "/b", byteCount: 10, status: .succeeded),
            TransferJob(direction: .download, sourcePath: "/c", destinationPath: "/d", byteCount: 20, status: .succeeded),
            TransferJob(direction: .upload, sourcePath: "/e", destinationPath: "/f", status: .failed(message: "No")),
            TransferJob(direction: .download, sourcePath: "/g", destinationPath: "/h", status: .running(progress: 0.5, bytesPerSecond: 100)),
            TransferJob(direction: .upload, sourcePath: "/i", destinationPath: "/j", status: .queued)
        ]

        let stats = TransferStatsCalculator.calculate(from: jobs)

        XCTAssertEqual(stats.uploadCount, 3)
        XCTAssertEqual(stats.downloadCount, 2)
        XCTAssertEqual(stats.bytesUploaded, 10)
        XCTAssertEqual(stats.bytesDownloaded, 20)
        XCTAssertEqual(stats.successfulTransfers, 2)
        XCTAssertEqual(stats.failedTransfers, 1)
        XCTAssertEqual(stats.activeTransfers, 1)
        XCTAssertEqual(stats.queuedTransfers, 1)
    }
}
