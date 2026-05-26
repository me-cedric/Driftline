import XCTest
@testable import DriftlineCore

final class RsyncTransferClientTests: XCTestCase {
    func testRsyncProgressParserReadsPercentAndSpeed() {
        let parsed = RsyncProgressParser.progress(from: "      1.23M  42%  10.50MB/s    0:00:01")

        XCTAssertEqual(parsed?.progress, 0.42)
        XCTAssertEqual(parsed?.bytesPerSecond, 10_500_000)
    }

    func testRsyncCommandBuilderUsesStrictSSHTransport() throws {
        let profile = ServerProfile(displayName: "Server", host: "example.com", port: 2222, protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)
        let job = TransferJob(direction: .upload, sourcePath: "/tmp/a.txt", destinationPath: "/var/www/a.txt")

        let arguments = try RsyncCommandBuilder.arguments(for: job, profile: profile)

        XCTAssertTrue(arguments.contains("-az"))
        XCTAssertTrue(arguments.contains("--progress"))
        XCTAssertTrue(arguments.contains("-e"))
        let sshCommand = arguments[arguments.firstIndex(of: "-e")! + 1]
        XCTAssertTrue(sshCommand.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(sshCommand.contains("UserKnownHostsFile="))
        XCTAssertTrue(arguments.contains("deploy@example.com:'/var/www/a.txt'"))
    }

    func testRsyncTransferClientPublishesProgressAndSuccess() async throws {
        let executor = ScriptedStreamingExecutor(events: [
            .standardOutput("      1.00M  50%  2.00MB/s    0:00:01"),
            .finished(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""))
        ])
        let client = SystemRsyncTransferClient(streamingExecutor: executor)
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)
        let job = TransferJob(direction: .upload, sourcePath: "/tmp/a.txt", destinationPath: "/tmp/a.txt")
        let recorder = TransferUpdateRecorder()

        try await client.enqueue(job, profile: profile) { update in
            await recorder.record(update)
        }
        let updates = await recorder.updates

        XCTAssertTrue(updates.contains { update in
            if case .running(let progress, let speed) = update.status {
                return progress == 0.5 && speed == 2_000_000
            }
            return false
        })
        XCTAssertEqual(updates.last?.status, .succeeded)
    }

    func testRsyncTransferClientCancelRequestsExecutorCancellation() async throws {
        let executor = CancellableScriptedStreamingExecutor(events: [])
        let client = SystemRsyncTransferClient(streamingExecutor: executor)

        try await client.cancel(id: TransferJobID())

        XCTAssertTrue(executor.didCancel)
    }
}

private struct ScriptedStreamingExecutor: StreamingProcessExecuting {
    var events: [ProcessOutputEvent]

    func stream(executable: String, arguments: [String], timeout: TimeInterval) -> AsyncThrowingStream<ProcessOutputEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private final class CancellableScriptedStreamingExecutor: CancellableStreamingProcessExecuting, @unchecked Sendable {
    private let events: [ProcessOutputEvent]
    private let queue = DispatchQueue(label: "app.driftline.tests.cancellable-streaming-executor")
    private var cancelled = false

    var didCancel: Bool {
        queue.sync { cancelled }
    }

    init(events: [ProcessOutputEvent]) {
        self.events = events
    }

    func stream(executable: String, arguments: [String], timeout: TimeInterval) -> AsyncThrowingStream<ProcessOutputEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func cancelAll() async {
        queue.sync {
            cancelled = true
        }
    }
}

private actor TransferUpdateRecorder {
    private(set) var updates: [TransferJob] = []

    func record(_ update: TransferJob) {
        updates.append(update)
    }
}
