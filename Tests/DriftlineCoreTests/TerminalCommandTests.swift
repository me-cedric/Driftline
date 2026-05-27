@testable import DriftlineCore
import XCTest

final class TerminalCommandTests: XCTestCase {
    func testSSHCommandDoesNotExposePasswordCredential() throws {
        let profile = ServerProfile(
            displayName: "Staging",
            host: "staging.example.com",
            port: 2222,
            protocolKind: .sftp,
            username: "deploy",
            authenticationMethod: .password(CredentialReference(service: "driftline", account: "staging"))
        )

        let command = try TerminalCommandFactory.sshCommand(for: profile)

        XCTAssertEqual(command.executable, "ssh")
        XCTAssertEqual(command.arguments, ["-p", "2222", "deploy@staging.example.com"])
        XCTAssertFalse(command.displayString.contains("password"))
    }
}
