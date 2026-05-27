@testable import DriftlineCore
import XCTest

final class NativeSFTPClientTests: XCTestCase {
    func testPassphraseProtectedOpenSSHEd25519KeyParsesWithCorrectPassphrase() throws {
        let sshKeygen = try XCTUnwrap(Self.executablePath(named: "ssh-keygen"), "ssh-keygen is required for encrypted OpenSSH key coverage.")
        let passphrase = "driftline-test-passphrase"
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("driftline-key-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let keyURL = temp.appendingPathComponent("id_ed25519")
        try Self.run(sshKeygen, arguments: [
            "-q",
            "-t", "ed25519",
            "-N", passphrase,
            "-f", keyURL.path,
        ])

        let contents = try String(contentsOf: keyURL, encoding: .utf8)
        XCTAssertNoThrow(try NativeSFTPPrivateKeyParser.parse(contents: contents, passphrase: passphrase))
        XCTAssertThrowsError(try NativeSFTPPrivateKeyParser.parse(contents: contents, passphrase: "wrong-passphrase"))
    }

    func testNativeSFTPClientAgentAuthProvidesUsefulError() async throws {
        let client = NativeSFTPClient(
            credentialStore: InMemoryCredentialStore(),
            hostTrustStore: InMemoryHostTrustStore()
        )
        let profile = ServerProfile(
            displayName: "AgentTest",
            host: "example.com",
            protocolKind: .sftp,
            username: "deploy",
            authenticationMethod: .agent
        )

        do {
            _ = try await client.connect(to: profile)
            XCTFail("Expected agent auth to throw nativeBackendUnavailable.")
        } catch let RemoteClientError.nativeBackendUnavailable(message) {
            XCTAssertTrue(message.contains("SSH"), "Error message should mention SSH, got: \(message)")
        }
    }

    func testNativeSFTPClientFailsPasswordProfilesWithoutStoredCredential() async throws {
        let reference = CredentialReference(service: "app.driftline.test", account: "deploy@example.com")
        let client = NativeSFTPClient(
            credentialStore: InMemoryCredentialStore(),
            hostTrustStore: InMemoryHostTrustStore()
        )
        let profile = ServerProfile(
            displayName: "Native",
            host: "example.com",
            protocolKind: .sftp,
            username: "deploy",
            authenticationMethod: .password(reference)
        )

        do {
            _ = try await client.connect(to: profile)
            XCTFail("Expected missing Keychain credential to fail authentication.")
        } catch RemoteClientError.authenticationFailed {
            XCTAssertTrue(true)
        }
    }

    private static func executablePath(named name: String) -> String? {
        ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init)
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private static func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(
                domain: "NativeSFTPClientTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
