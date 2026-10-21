@testable import DriftlineCore
import XCTest

/// Runs against `scripts/integration-ftp-server.sh start` (vsftpd with a self-signed certificate).
final class FTPIntegrationTests: XCTestCase {
    func testPlainFTPWhenHarnessEnabled() async throws {
        try await self.exercise(protocolKind: .ftp, portVariable: "DRIFTLINE_TEST_FTP_PORT", defaultPort: 2121, expectsCertificatePrompt: false)
    }

    func testExplicitFTPSWhenHarnessEnabled() async throws {
        try await self.exercise(protocolKind: .ftps, portVariable: "DRIFTLINE_TEST_FTP_PORT", defaultPort: 2121, expectsCertificatePrompt: true)
    }

    func testImplicitFTPSWhenHarnessEnabled() async throws {
        // Driftline uses implicit TLS on port 990, so the harness publishes the implicit server there.
        try await self.exercise(protocolKind: .ftps, portVariable: "DRIFTLINE_TEST_FTPS_IMPLICIT_PORT", defaultPort: 990, expectsCertificatePrompt: true)
    }

    private func exercise(protocolKind: TransferProtocolKind, portVariable: String, defaultPort: Int, expectsCertificatePrompt: Bool) async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["DRIFTLINE_INTEGRATION_FTP"] == "1", let password = env["DRIFTLINE_TEST_PASSWORD"] else {
            throw XCTSkip("Set DRIFTLINE_INTEGRATION_FTP=1 and DRIFTLINE_TEST_PASSWORD after running scripts/integration-ftp-server.sh start")
        }
        let port = Int(env[portVariable] ?? "\(defaultPort)") ?? defaultPort
        let (profile, credentials) = try await self.profile(protocolKind: protocolKind, port: port, password: password)
        let trustStore = InMemoryHostTrustStore()
        let pins = FTPTLSPinCache()
        let client = FTPClient(credentialStore: credentials, hostTrustStore: trustStore, pinCache: pins)
        let transfers = FTPTransferClient(credentialStore: credentials, hostTrustStore: trustStore, pinCache: pins)

        if expectsCertificatePrompt {
            do {
                _ = try await client.connect(to: profile)
                XCTFail("Expected the self-signed certificate to need trust")
            } catch let RemoteClientError.hostNotTrusted(host, port, algorithm, fingerprint, _) {
                XCTAssertTrue(fingerprint.hasPrefix("SHA256:"))
                try await trustStore.trust(HostTrustRecord(host: host, port: port, algorithm: algorithm, fingerprint: fingerprint))
            }
        }
        let session = try await client.connect(to: profile)

        let folder = "~/driftline \(protocolKind.rawValue) \(UUID().uuidString.prefix(8))"
        try await client.createFolder(named: String(folder.dropFirst(2)), in: "~", profile: profile, session: session)
        let exists = try await client.itemExists(at: folder, profile: profile, session: session)
        XCTAssertTrue(exists)

        let local = FileManager.default.temporaryDirectory.appendingPathComponent("driftline-ftp-\(UUID().uuidString)")
        let localTree = local.appendingPathComponent("tree")
        try FileManager.default.createDirectory(at: localTree.appendingPathComponent("nested dir"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }
        try Data("root file".utf8).write(to: localTree.appendingPathComponent("a.txt"))
        try Data(repeating: 7, count: 300_000).write(to: localTree.appendingPathComponent("nested dir/b.bin"))

        let upload = TransferJob(direction: .upload, sourcePath: localTree.path, destinationPath: "\(folder)/tree", isFolder: true)
        try await transfers.enqueue(upload, profile: profile)
        let uploadStatus = await transfers.jobs().first { $0.id == upload.id }?.status
        XCTAssertEqual(uploadStatus, .succeeded)

        let listing = try await client.listDirectory(at: "\(folder)/tree", profile: profile, session: session, preferences: FileListPreferences())
        XCTAssertEqual(Set(listing.map(\.name)), ["a.txt", "nested dir"])

        try await client.renameItem(at: "\(folder)/tree/a.txt", to: "renamed a.txt", profile: profile, session: session)

        let downloaded = local.appendingPathComponent("downloaded")
        let download = TransferJob(direction: .download, sourcePath: "\(folder)/tree", destinationPath: downloaded.path, isFolder: true)
        try await transfers.enqueue(download, profile: profile)
        let downloadStatus = await transfers.jobs().first { $0.id == download.id }?.status
        XCTAssertEqual(downloadStatus, .succeeded)
        XCTAssertEqual(try String(contentsOf: downloaded.appendingPathComponent("renamed a.txt"), encoding: .utf8), "root file")
        XCTAssertEqual(try Data(contentsOf: downloaded.appendingPathComponent("nested dir/b.bin")).count, 300_000)

        try await client.deleteItem(at: folder, profile: profile, session: session)
        let existsAfterDelete = try await client.itemExists(at: folder, profile: profile, session: session)
        XCTAssertFalse(existsAfterDelete)

        try await credentials.saveString("wrong-password", reference: CredentialReference(service: "app.driftline.integration", account: "ftp"))
        do {
            _ = try await client.connect(to: profile)
            XCTFail("Expected a wrong password to fail")
        } catch {
            XCTAssertEqual(error as? RemoteClientError, .authenticationFailed)
        }
    }

    private func profile(protocolKind: TransferProtocolKind, port: Int, password: String) async throws -> (ServerProfile, InMemoryCredentialStore) {
        let reference = CredentialReference(service: "app.driftline.integration", account: "ftp")
        let credentials = InMemoryCredentialStore()
        try await credentials.saveString(password, reference: reference)
        let profile = ServerProfile(
            displayName: "FTP Integration",
            host: "127.0.0.1",
            port: port,
            protocolKind: protocolKind,
            username: ProcessInfo.processInfo.environment["DRIFTLINE_TEST_USER"] ?? "driftline",
            authenticationMethod: .password(reference)
        )
        return (profile, credentials)
    }
}
