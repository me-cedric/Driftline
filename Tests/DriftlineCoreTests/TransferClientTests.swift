@testable import DriftlineCore
import XCTest

final class TransferClientTests: XCTestCase {
    func testSCPUploadCommandUsesUppercasePortAndRemoteDestination() throws {
        let profile = ServerProfile(displayName: "Server", host: "example.com", port: 2222, protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)
        let job = TransferJob(direction: .upload, sourcePath: "/tmp/site/index.html", destinationPath: "/var/www/index.html")

        let arguments = try TransferCommandBuilder.scpArguments(for: job, profile: profile)

        XCTAssertEqual(Array(arguments.prefix(2)), ["-P", "2222"])
        XCTAssertTrue(arguments.contains("/tmp/site/index.html"))
        XCTAssertTrue(arguments.contains("deploy@example.com:'/var/www/index.html'"))
    }

    func testSCPDownloadCommandUsesRemoteSourceAndLocalDestination() throws {
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .privateKey(path: "~/.ssh/id_ed25519", passphrase: nil))
        let job = TransferJob(direction: .download, sourcePath: "/var/log/app.log", destinationPath: "~/Downloads/app.log")

        let arguments = try TransferCommandBuilder.scpArguments(for: job, profile: profile)

        XCTAssertTrue(arguments.contains("-i"))
        XCTAssertTrue(arguments.contains(NSString(string: "~/.ssh/id_ed25519").expandingTildeInPath))
        XCTAssertTrue(arguments.contains("deploy@example.com:'/var/log/app.log'"))
        XCTAssertTrue(arguments.contains(NSString(string: "~/Downloads/app.log").expandingTildeInPath))
    }

    func testSystemSCPTransferClientMarksSucceededJob() async throws {
        let executor = RecordingTransferProcessExecutor(result: ProcessResult(exitCode: 0, standardOutput: "", standardError: ""))
        let client = SystemSCPTransferClient(processExecutor: executor)
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)
        let job = TransferJob(direction: .upload, sourcePath: "/tmp/a.txt", destinationPath: "/tmp/a.txt")

        try await client.enqueue(job, profile: profile)
        let jobs = await client.jobs()

        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?.status, .succeeded)
        let invocation = await executor.recordedInvocation()
        XCTAssertEqual(invocation?.executable, "/usr/bin/scp")
    }

    func testSystemSCPTransferClientRedactsFailedJobError() async throws {
        let executor = RecordingTransferProcessExecutor(result: ProcessResult(exitCode: 1, standardOutput: "", standardError: "password=hunter2 denied"))
        let client = SystemSCPTransferClient(processExecutor: executor)
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)
        let job = TransferJob(direction: .upload, sourcePath: "/tmp/a.txt", destinationPath: "/tmp/a.txt")

        try await client.enqueue(job, profile: profile)
        let jobs = await client.jobs()

        guard case let .failed(message) = jobs.first?.status else {
            return XCTFail("Expected failed transfer")
        }
        XCTAssertFalse(message.contains("hunter2"))
        XCTAssertTrue(message.contains("<redacted>"))
    }
}

private actor RecordingTransferProcessExecutor: SystemProcessExecuting {
    struct Invocation {
        var executable: String
        var arguments: [String]
    }

    private let result: ProcessResult
    private(set) var invocation: Invocation?

    init(result: ProcessResult) {
        self.result = result
    }

    func run(executable: String, arguments: [String], timeout _: TimeInterval) async throws -> ProcessResult {
        self.invocation = Invocation(executable: executable, arguments: arguments)
        return self.result
    }

    func recordedInvocation() -> Invocation? {
        self.invocation
    }
}
