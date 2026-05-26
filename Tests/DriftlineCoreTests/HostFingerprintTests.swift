import XCTest
@testable import DriftlineCore

final class HostFingerprintTests: XCTestCase {
    func testSystemHostFingerprintProviderParsesSSHKeygenOutput() {
        let provider = SystemHostFingerprintProvider(processExecutor: RecordingHostProcessExecutor(results: []))

        let fingerprint = provider.parseKeygenOutput("256 SHA256:abc123 example.com (ED25519)\n", host: "example.com", port: 22)

        XCTAssertEqual(fingerprint?.host, "example.com")
        XCTAssertEqual(fingerprint?.port, 22)
        XCTAssertEqual(fingerprint?.algorithm, "ED25519")
        XCTAssertEqual(fingerprint?.fingerprint, "SHA256:abc123")
    }

    func testSystemSFTPClientBlocksUnknownHostUntilTrusted() async throws {
        let trustStore = InMemoryHostTrustStore()
        let fingerprintProvider = StaticHostFingerprintProvider(fingerprint: HostFingerprint(host: "example.com", port: 22, algorithm: "ED25519", fingerprint: "SHA256:abc123"))
        let client = SystemSFTPClient(hostTrustStore: trustStore, hostFingerprintProvider: fingerprintProvider)
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)

        do {
            _ = try await client.connect(to: profile)
            XCTFail("Expected host trust error")
        } catch RemoteClientError.hostNotTrusted(let host, let port, let algorithm, let fingerprint, _) {
            XCTAssertEqual(host, "example.com")
            XCTAssertEqual(port, 22)
            XCTAssertEqual(algorithm, "ED25519")
            XCTAssertEqual(fingerprint, "SHA256:abc123")
        }

        try await trustStore.trust(HostTrustRecord(host: "example.com", port: 22, algorithm: "ED25519", fingerprint: "SHA256:abc123"))
        let session = try await client.connect(to: profile)

        XCTAssertEqual(session.state, .connected)
    }

    func testSystemSFTPClientBlocksChangedHostFingerprint() async throws {
        let trustStore = InMemoryHostTrustStore(records: [
            HostTrustRecord(host: "example.com", port: 22, algorithm: "ED25519", fingerprint: "SHA256:old")
        ])
        let fingerprintProvider = StaticHostFingerprintProvider(fingerprint: HostFingerprint(host: "example.com", port: 22, algorithm: "ED25519", fingerprint: "SHA256:new"))
        let client = SystemSFTPClient(hostTrustStore: trustStore, hostFingerprintProvider: fingerprintProvider)
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)

        await XCTAssertThrowsErrorAsync(try await client.connect(to: profile)) { error in
            XCTAssertEqual(error as? RemoteClientError, .hostFingerprintChanged)
        }
    }
}

private struct StaticHostFingerprintProvider: HostFingerprintProviding {
    var fingerprint: HostFingerprint

    func fingerprint(host: String, port: Int) async throws -> HostFingerprint {
        fingerprint
    }
}

private struct RecordingHostProcessExecutor: SystemProcessExecuting {
    var results: [ProcessResult]

    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        results.first ?? ProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    _ handler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        handler(error)
    }
}
