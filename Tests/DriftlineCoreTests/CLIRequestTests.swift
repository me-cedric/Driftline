@testable import DriftlineCore
import XCTest

final class CLIRequestTests: XCTestCase {
    func testCLIRequestStoreSavesAndConsumesRequest() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftlineTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("request.json")
        let request = CLIRequest(localPath: "/tmp/example", openInNewTab: true, requestedAt: Date(timeIntervalSince1970: 1))

        try CLIRequestStore.save(request, url: url)
        let consumed = try CLIRequestStore.consume(url: url)

        XCTAssertEqual(consumed, request)
        XCTAssertNil(try CLIRequestStore.consume(url: url))
    }
}
