@testable import DriftlineCore
import XCTest

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
        let client = SystemSFTPClient(
            processExecutor: SequencedProcessExecutor(results: [
                ProcessResult(exitCode: 255, standardOutput: "", standardError: "No ED25519 host key is known for example.com and you have requested strict checking.\r\nHost key verification failed.\r\n"),
                ProcessResult(exitCode: 0, standardOutput: "Remote working directory: /\n", standardError: ""),
            ]),
            hostTrustStore: trustStore,
            hostFingerprintProvider: fingerprintProvider
        )
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)

        do {
            _ = try await client.connect(to: profile)
            XCTFail("Expected host trust error")
        } catch let RemoteClientError.hostNotTrusted(host, port, algorithm, fingerprint, _) {
            XCTAssertEqual(host, "example.com")
            XCTAssertEqual(port, 22)
            XCTAssertEqual(algorithm, "ED25519")
            XCTAssertEqual(fingerprint, "SHA256:abc123")
        }

        try await trustStore.trust(HostTrustRecord(host: "example.com", port: 22, algorithm: "ED25519", fingerprint: "SHA256:abc123"))
        let session = try await client.connect(to: profile)

        XCTAssertEqual(session.state, .connected)
    }

    func testSystemSFTPClientBlocksChangedHostFingerprint() async {
        let trustStore = InMemoryHostTrustStore(records: [
            HostTrustRecord(host: "example.com", port: 22, algorithm: "ED25519", fingerprint: "SHA256:old"),
        ])
        let fingerprintProvider = StaticHostFingerprintProvider(fingerprint: HostFingerprint(host: "example.com", port: 22, algorithm: "ED25519", fingerprint: "SHA256:new"))
        let client = SystemSFTPClient(
            processExecutor: SequencedProcessExecutor(results: [
                ProcessResult(exitCode: 255, standardOutput: "", standardError: "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!\r\nHost key verification failed.\r\n"),
            ]),
            hostTrustStore: trustStore,
            hostFingerprintProvider: fingerprintProvider
        )
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)

        await XCTAssertThrowsErrorAsync {
            try await client.connect(to: profile)
        } handler: { error in
            XCTAssertEqual(error as? RemoteClientError, .hostFingerprintChanged)
        }
    }
}

private struct StaticHostFingerprintProvider: HostFingerprintProviding {
    var fingerprint: HostFingerprint

    func fingerprint(host _: String, port _: Int) async throws -> HostFingerprint {
        self.fingerprint
    }
}

private actor SequencedProcessExecutor: SystemProcessExecuting {
    private var results: [ProcessResult]

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(executable _: String, arguments _: [String], environment _: [String: String], standardInput _: Data?, timeout _: TimeInterval) async throws -> ProcessResult {
        self.results.count > 1 ? self.results.removeFirst() : self.results[0]
    }
}

private struct RecordingHostProcessExecutor: SystemProcessExecuting {
    var results: [ProcessResult]

    func run(executable _: String, arguments _: [String], environment _: [String: String], standardInput _: Data?, timeout _: TimeInterval) async throws -> ProcessResult {
        self.results.first ?? ProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> some Any,
    handler: (Error) -> Void,
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
