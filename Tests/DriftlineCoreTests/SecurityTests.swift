import XCTest
@testable import DriftlineCore

final class SecurityTests: XCTestCase {
    func testInMemoryCredentialStoreRoundTrip() async throws {
        let store = InMemoryCredentialStore()
        let reference = CredentialReference(service: "com.driftline.test", account: "user@example.com")
        let secret = Data("super-secret".utf8)

        try await store.save(secret: secret, reference: reference)
        let loaded = try await store.read(reference: reference)
        XCTAssertEqual(loaded, secret)

        try await store.delete(reference: reference)
        let deleted = try await store.read(reference: reference)
        XCTAssertNil(deleted)
    }

    func testCredentialStoreStringHelpersRoundTrip() async throws {
        let store = InMemoryCredentialStore()
        let reference = CredentialReference(service: "com.driftline.test", account: "string")

        try await store.saveString("secret text", reference: reference)

        let loaded = try await store.readString(reference: reference)
        XCTAssertEqual(loaded, "secret text")
    }

    func testRedactorMasksCommonSecretShapes() {
        let redactor = Redactor()
        let output = redactor.redact("password=hunter2 token: abc123 passphrase='open sesame'")

        XCTAssertFalse(output.contains("hunter2"))
        XCTAssertFalse(output.contains("abc123"))
        XCTAssertFalse(output.contains("open sesame"))
        XCTAssertTrue(output.contains("<redacted>"))
    }
}
