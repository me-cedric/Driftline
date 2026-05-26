import XCTest
@testable import DriftlineCore

final class NativeSFTPClientTests: XCTestCase {
    func testNativeSFTPClientReportsPrivateKeyAuthAsPlanned() async throws {
        let passphraseReference = CredentialReference(service: "app.driftline.test", account: "deploy@example.com")
        let credentialStore = InMemoryCredentialStore()
        try await credentialStore.saveString("phrase", reference: passphraseReference)
        let client = NativeSFTPClient(
            credentialStore: credentialStore,
            hostTrustStore: InMemoryHostTrustStore()
        )
        let profile = ServerProfile(
            displayName: "Native",
            host: "example.com",
            protocolKind: .sftp,
            username: "deploy",
            authenticationMethod: .privateKey(path: "/Users/example/.ssh/id_ed25519", passphrase: passphraseReference)
        )

        do {
            _ = try await client.connect(to: profile)
            XCTFail("Expected private key auth to remain guarded until native key parsing is implemented.")
        } catch RemoteClientError.unsupportedAuthentication(let message) {
            XCTAssertTrue(message.contains("Passphrase-protected"))
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
}
