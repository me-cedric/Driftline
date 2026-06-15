@testable import DriftlineCore
import XCTest

final class SFTPClientTests: XCTestCase {
    func testRemoteFindParserParsesAndSortsListing() {
        let output = """
        f\t42\t1710000000.0\t-rw-r--r--\tdeploy\tstaff\t/var/www/index.html
        d\t0\t1710000100.0\tdrwxr-xr-x\tdeploy\tstaff\t/var/www/assets
        f\t8\t1710000200.0\t-rw-r--r--\tdeploy\tstaff\t/var/www/.env
        """

        let items = RemoteFindParser.parse(output, preferences: FileListPreferences())

        XCTAssertEqual(items.map(\.name), ["assets", "index.html"])
        XCTAssertEqual(items.first?.kind, .folder)
        XCTAssertEqual(items.last?.size, 42)
        XCTAssertEqual(items.last?.owner, "deploy")
    }

    func testRemoteFindParserCanShowHiddenFiles() {
        let output = "f\t8\t1710000200.0\t-rw-r--r--\tdeploy\tstaff\t/var/www/.env\n"

        let items = RemoteFindParser.parse(output, preferences: FileListPreferences(showHiddenFiles: true))

        XCTAssertEqual(items.first?.name, ".env")
        XCTAssertEqual(items.first?.isHidden, true)
    }

    func testSSHCommandBuilderRejectsPasswordAuthForSystemExecution() throws {
        let profile = ServerProfile(
            displayName: "Password Server",
            host: "example.com",
            protocolKind: .sftp,
            username: "deploy",
            authenticationMethod: .password(CredentialReference(service: "driftline", account: "deploy@example.com"))
        )

        XCTAssertThrowsError(try SSHCommandBuilder.remoteListArguments(for: profile, path: "/")) { error in
            XCTAssertEqual(error as? RemoteClientError, .unsupportedAuthentication("Password authentication is stored safely, but system SSH execution cannot use passwords without exposing them. Use SSH agent or private key authentication for this build."))
        }
    }

    func testSSHCommandBuilderExpandsUserHomeRemotePaths() {
        XCTAssertEqual(SSHCommandBuilder.remoteFindCommand(path: "~"), "LC_ALL=C find \"$HOME\" -maxdepth 1 -mindepth 1 -printf '%y\\t%s\\t%T@\\t%M\\t%u\\t%g\\t%p\\n'")
        XCTAssertEqual(SSHCommandBuilder.remoteFindCommand(path: "~/Sites"), "LC_ALL=C find \"$HOME\"/'Sites' -maxdepth 1 -mindepth 1 -printf '%y\\t%s\\t%T@\\t%M\\t%u\\t%g\\t%p\\n'")
    }

    func testSystemSFTPClientUsesStructuredSSHArgumentsAndParsesOutput() async throws {
        let executor = RecordingProcessExecutor(result: ProcessResult(
            exitCode: 0,
            standardOutput: "f\t42\t1710000000.0\t-rw-r--r--\tdeploy\tstaff\t/home/deploy/readme.txt\n",
            standardError: ""
        ))
        let client = SystemSFTPClient(processExecutor: executor)
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)
        let session = try await client.connect(to: profile)

        let items = try await client.listDirectory(at: "/home/deploy", profile: profile, session: session, preferences: FileListPreferences())
        let invocation = await executor.invocation

        XCTAssertEqual(items.first?.name, "readme.txt")
        XCTAssertEqual(invocation?.executable, "/usr/bin/ssh")
        XCTAssertEqual(invocation?.arguments.last, SSHCommandBuilder.remoteFindCommand(path: "/home/deploy"))
        XCTAssertTrue(invocation?.arguments.contains("deploy@example.com") == true)
    }
}

private actor RecordingProcessExecutor: SystemProcessExecuting {
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
}
