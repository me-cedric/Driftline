@testable import DriftlineCore
import XCTest

final class DiagnosticsRecorderTests: XCTestCase {
    func testDiagnosticsRecorderWritesRedactedEvents() async throws {
        let url = self.temporaryFileURL("diagnostics.jsonl")
        let recorder = DiagnosticsRecorder(fileURL: url)

        await recorder.record(level: .error, category: "connection", message: "password=super-secret failed")

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains(#""level":"error""#))
        XCTAssertTrue(contents.contains("password=<redacted>"))
        XCTAssertFalse(contents.contains("super-secret"))
    }

    private func temporaryFileURL(_ filename: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(filename)
    }
}
