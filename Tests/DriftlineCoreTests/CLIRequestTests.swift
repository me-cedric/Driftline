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

    func testCLIRequestStoreSavesBookmarkIntent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftlineTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("request.json")
        let request = CLIRequest(intent: .openBookmark("staging"), openInNewTab: false, requestedAt: Date(timeIntervalSince1970: 2))

        try CLIRequestStore.save(request, url: url)
        let consumed = try CLIRequestStore.consume(url: url)

        XCTAssertEqual(consumed, request)
        XCTAssertEqual(consumed?.bookmarkName, "staging")
    }

    func testCLIRequestDecodesLegacyLocalPathPayload() throws {
        let data = Data("""
        {
          "localPath": "/tmp/example",
          "openInNewTab": true,
          "requestedAt": "1970-01-01T00:00:01Z"
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let request = try decoder.decode(CLIRequest.self, from: data)

        XCTAssertEqual(request.localPath, "/tmp/example")
        XCTAssertTrue(request.openInNewTab)
    }
}
