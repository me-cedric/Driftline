@testable import DriftlineCore
import XCTest

final class SFTPClientTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!

    func testLongListingParserReadsSFTPOutput() {
        let output = """
        sftp> pwd
        Remote working directory: /var/www
        sftp> ls -lan
        drwxr-xr-x    5 1000     1000         4096 Oct 20 09:15 .
        drwxr-xr-x    3 0        0            4096 Jan  3  2024 ..
        -rw-r--r--    1 1000     1000           42 Oct 20 09:15 index file.html
        drwxr-xr-x    2 1000     1000         4096 Mar 14  2025 assets
        lrwxrwxrwx    1 1000     1000           11 Oct 01 10:00 current
        -rw-r--r--    1 1000     1000            8 Oct 19 08:00 .hidden
        -rw-r--r--    1 1000     1000            3  epoch.txt
        """

        let directory = SFTPLongListingParser.workingDirectory(in: output)
        let items = SFTPLongListingParser.parse(output, directory: directory ?? "", preferences: FileListPreferences(), now: self.now)

        XCTAssertEqual(directory, "/var/www")
        XCTAssertEqual(items.map(\.name), ["assets", "current", "epoch.txt", "index file.html"])
        XCTAssertEqual(items.first?.kind, .folder)
        XCTAssertEqual(items.first { $0.name == "current" }?.kind, .symbolicLink)
        let file = items.first { $0.name == "index file.html" }
        XCTAssertEqual(file?.path, "/var/www/index file.html")
        XCTAssertEqual(file?.size, 42)
        XCTAssertEqual(file?.owner, "1000")
        XCTAssertEqual(Calendar.current.component(.year, from: file?.modifiedAt ?? .distantPast), 2026)
        XCTAssertEqual(Calendar.current.component(.year, from: items.first?.modifiedAt ?? .distantPast), 2025)
        XCTAssertNil(items.first { $0.name == "epoch.txt" }?.modifiedAt)
    }

    func testLongListingParserCanShowHiddenFiles() {
        let output = "-rw-r--r--    1 1000     1000            8 Oct 19 08:00 .hidden\n"

        let items = SFTPLongListingParser.parse(output, directory: "/", preferences: FileListPreferences(showHiddenFiles: true), now: self.now)

        XCTAssertEqual(items.first?.path, "/.hidden")
        XCTAssertEqual(items.first?.isHidden, true)
    }

    func testListingDateFromLastDecemberUsesPreviousYear() {
        let date = SFTPLongListingParser.date(month: 12, day: 30, timeOrYear: "23:00", now: self.now)

        XCTAssertEqual(Calendar.current.component(.year, from: date ?? .distantPast), 2025)
    }

    func testBatchCommandsQuotePathsAndMapHome() throws {
        XCTAssertEqual(try SFTPBatchCommandBuilder.listCommands(path: "~"), "pwd\nls -lan\n")
        XCTAssertEqual(try SFTPBatchCommandBuilder.listCommands(path: "~/Sites"), "cd \"Sites\"\npwd\nls -lan\n")
        XCTAssertEqual(try SFTPBatchCommandBuilder.createFolderCommand(name: "New \"Folder\"", in: "/var/www"), "mkdir \"/var/www/New \\\"Folder\\\"\"\n")
        XCTAssertEqual(try SFTPBatchCommandBuilder.renameCommand(path: "~/old name.txt", newName: "new name.txt"), "rename \"old name.txt\" \"new name.txt\"\n")
        XCTAssertEqual(try SFTPBatchCommandBuilder.removeFileCommand(path: "/a\\b"), "rm \"/a\\\\b\"\n")
    }

    func testBatchCommandsRejectLineBreaks() {
        XCTAssertThrowsError(try SFTPBatchCommandBuilder.removeFileCommand(path: "/tmp/x\nrm /etc/passwd"))
    }

    func testPasswordProfileUsesAskPassFriendlyOptions() throws {
        let profile = ServerProfile(
            displayName: "Password Server",
            host: "example.com",
            protocolKind: .sftp,
            username: "deploy",
            authenticationMethod: .password(CredentialReference(service: "driftline", account: "deploy@example.com"))
        )

        let arguments = try SSHCommandBuilder.sftpBatchArguments(for: profile, knownHostsURL: nil)

        XCTAssertEqual(Array(arguments.prefix(2)), ["-P", "22"])
        XCTAssertTrue(arguments.contains("BatchMode=no"))
        XCTAssertTrue(arguments.contains("PubkeyAuthentication=no"))
        XCTAssertTrue(arguments.contains("NumberOfPasswordPrompts=1"))
        // ssh keeps the first value of an option, so BatchMode=no must come before the -b that adds BatchMode=yes.
        XCTAssertLessThan(try XCTUnwrap(arguments.firstIndex(of: "BatchMode=no")), try XCTUnwrap(arguments.firstIndex(of: "-b")))
        XCTAssertEqual(arguments.last, "deploy@example.com")
    }

    func testPrivateKeyProfileOffersOnlyThatKey() throws {
        let profile = ServerProfile(displayName: "Key", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .privateKey(path: "/keys/id", passphrase: nil))

        let arguments = try SSHCommandBuilder.baseArguments(for: profile, knownHostsURL: nil)

        XCTAssertTrue(arguments.contains("BatchMode=yes"))
        XCTAssertTrue(arguments.contains("IdentitiesOnly=yes"))
        XCTAssertTrue(arguments.contains("HostKeyAlgorithms=+ssh-rsa"))
    }

    func testAskPassSessionServesSecretThroughHelper() throws {
        let session = try SSHAskPassSession(secret: "s3cret value")
        defer { session.close() }
        let process = Process()
        let output = Pipe()
        process.executableURL = try URL(fileURLWithPath: XCTUnwrap(session.environment["SSH_ASKPASS"]))
        process.environment = session.environment
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "s3cret value\n")
        XCTAssertFalse(session.environment.values.contains { $0.contains("s3cret") })
    }

    func testSystemSFTPClientRunsSFTPBatchAndParsesOutput() async throws {
        let executor = RecordingProcessExecutor(result: ProcessResult(
            exitCode: 0,
            standardOutput: "Remote working directory: /home/deploy\n-rw-r--r--    1 1000     1000           42 Jan  1  2025 readme.txt\n",
            standardError: ""
        ))
        let client = SystemSFTPClient(processExecutor: executor, knownHostsURL: nil)
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)
        let session = try await client.connect(to: profile)

        let items = try await client.listDirectory(at: "/home/deploy", profile: profile, session: session, preferences: FileListPreferences())
        let invocation = await executor.invocation

        XCTAssertEqual(items.first?.path, "/home/deploy/readme.txt")
        XCTAssertEqual(invocation?.executable, "/usr/bin/sftp")
        XCTAssertEqual(invocation?.standardInput, "cd \"/home/deploy\"\npwd\nls -lan\n")
        XCTAssertEqual(invocation?.arguments.last, "deploy@example.com")
    }

    func testSystemSFTPClientMapsPermissionDeniedToAuthenticationFailure() async {
        let executor = RecordingProcessExecutor(result: ProcessResult(exitCode: 255, standardOutput: "", standardError: "deploy@example.com: Permission denied (publickey,password)."))
        let client = SystemSFTPClient(processExecutor: executor, knownHostsURL: nil)
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)

        do {
            _ = try await client.connect(to: profile)
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertEqual(error as? RemoteClientError, .authenticationFailed)
        }
    }

    func testSystemSFTPClientRefusesToDeleteHome() async throws {
        let executor = RecordingProcessExecutor(result: ProcessResult(exitCode: 0, standardOutput: "", standardError: ""))
        let client = SystemSFTPClient(processExecutor: executor, knownHostsURL: nil)
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)
        let session = try await client.connect(to: profile)

        do {
            try await client.deleteItem(at: "~", profile: profile, session: session)
            XCTFail("Expected refusal")
        } catch {
            XCTAssertNotNil(error as? RemoteClientError)
        }
    }
}

private actor RecordingProcessExecutor: SystemProcessExecuting {
    struct Invocation {
        var executable: String
        var arguments: [String]
        var standardInput: String?
    }

    private let result: ProcessResult
    private(set) var invocation: Invocation?

    init(result: ProcessResult) {
        self.result = result
    }

    func run(executable: String, arguments: [String], environment _: [String: String], standardInput: Data?, timeout _: TimeInterval) async throws -> ProcessResult {
        self.invocation = Invocation(executable: executable, arguments: arguments, standardInput: standardInput.flatMap { String(data: $0, encoding: .utf8) })
        return self.result
    }
}
