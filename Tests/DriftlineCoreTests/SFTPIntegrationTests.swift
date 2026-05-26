import XCTest
@testable import DriftlineCore

final class SFTPIntegrationTests: XCTestCase {
    func testRealSFTPListCreateRenameDeleteWhenHarnessEnabled() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["DRIFTLINE_INTEGRATION_SFTP"] == "1" else {
            throw XCTSkip("Set DRIFTLINE_INTEGRATION_SFTP=1 after running scripts/integration-sftp-server.sh start")
        }

        let host = env["DRIFTLINE_TEST_HOST"] ?? "127.0.0.1"
        let port = Int(env["DRIFTLINE_TEST_PORT"] ?? "22222") ?? 22222
        let user = env["DRIFTLINE_TEST_USER"] ?? "driftline"
        let key = env["DRIFTLINE_TEST_KEY"] ?? ""
        let profile = ServerProfile(
            displayName: "Integration",
            host: host,
            port: port,
            protocolKind: .sftp,
            username: user,
            authenticationMethod: .privateKey(path: key, passphrase: nil),
            remoteDefaultPath: "/config"
        )
        let trustStore = InMemoryHostTrustStore()
        let fingerprintProvider = SystemHostFingerprintProvider()
        let firstClient = SystemSFTPClient(hostTrustStore: trustStore, hostFingerprintProvider: fingerprintProvider)

        do {
            _ = try await firstClient.connect(to: profile)
            XCTFail("Expected first connection to require trust")
        } catch RemoteClientError.hostNotTrusted(let host, let port, let algorithm, let fingerprint, let knownHostsLine) {
            try await trustStore.trust(HostTrustRecord(host: host, port: port, algorithm: algorithm, fingerprint: fingerprint, knownHostsLine: knownHostsLine))
            try await ManagedKnownHostsFile().trust(HostTrustRecord(host: host, port: port, algorithm: algorithm, fingerprint: fingerprint, knownHostsLine: knownHostsLine))
        }

        let session = try await firstClient.connect(to: profile)
        let folderName = "driftline-\(UUID().uuidString)"
        try await firstClient.createFolder(named: folderName, in: profile.remoteDefaultPath, profile: profile, session: session)
        let createdExists = try await firstClient.itemExists(at: "/config/\(folderName)", profile: profile, session: session)
        XCTAssertTrue(createdExists)

        let renamed = "\(folderName)-renamed"
        try await firstClient.renameItem(at: "/config/\(folderName)", to: renamed, profile: profile, session: session)
        let renamedExists = try await firstClient.itemExists(at: "/config/\(renamed)", profile: profile, session: session)
        XCTAssertTrue(renamedExists)

        try await firstClient.deleteItem(at: "/config/\(renamed)", profile: profile, session: session)
        let existsAfterDelete = try await firstClient.itemExists(at: "/config/\(renamed)", profile: profile, session: session)
        XCTAssertFalse(existsAfterDelete)
    }

    func testNativeSwiftPasswordSFTPListCreateRenameDeleteWhenHarnessEnabled() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["DRIFTLINE_NATIVE_INTEGRATION_SFTP"] == "1" else {
            throw XCTSkip("Set DRIFTLINE_TEST_PASSWORD and DRIFTLINE_NATIVE_INTEGRATION_SFTP=1 before running scripts/integration-sftp-server.sh start")
        }
        guard let password = env["DRIFTLINE_TEST_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Native Swift SFTP integration currently validates password auth; set DRIFTLINE_TEST_PASSWORD.")
        }

        let host = env["DRIFTLINE_TEST_HOST"] ?? "127.0.0.1"
        let port = Int(env["DRIFTLINE_TEST_PORT"] ?? "22222") ?? 22222
        let user = env["DRIFTLINE_TEST_USER"] ?? "driftline"
        let reference = CredentialReference(service: "app.driftline.integration", account: "\(user)@\(host)")
        let credentials = InMemoryCredentialStore()
        try await credentials.saveString(password, reference: reference)

        let profile = ServerProfile(
            displayName: "Native Integration",
            host: host,
            port: port,
            protocolKind: .sftp,
            username: user,
            authenticationMethod: .password(reference),
            remoteDefaultPath: "/config"
        )
        let trustStore = InMemoryHostTrustStore()
        let client = NativeSFTPClient(credentialStore: credentials, hostTrustStore: trustStore)

        do {
            _ = try await client.connect(to: profile)
            XCTFail("Expected first native connection to require explicit host trust.")
        } catch RemoteClientError.hostNotTrusted(let host, let port, let algorithm, let fingerprint, let knownHostsLine) {
            try await trustStore.trust(HostTrustRecord(host: host, port: port, algorithm: algorithm, fingerprint: fingerprint, knownHostsLine: knownHostsLine))
        }

        let session = try await client.connect(to: profile)

        let folderName = "driftline-native-\(UUID().uuidString)"
        try await client.createFolder(named: folderName, in: profile.remoteDefaultPath, profile: profile, session: session)
        let createdExists = try await client.itemExists(at: "/config/\(folderName)", profile: profile, session: session)
        XCTAssertTrue(createdExists)

        let renamed = "\(folderName)-renamed"
        try await client.renameItem(at: "/config/\(folderName)", to: renamed, profile: profile, session: session)
        let renamedExists = try await client.itemExists(at: "/config/\(renamed)", profile: profile, session: session)
        XCTAssertTrue(renamedExists)

        let listed = try await client.listDirectory(at: "/config", profile: profile, session: session, preferences: FileListPreferences(showHiddenFiles: true))
        XCTAssertTrue(listed.contains { $0.name == renamed && $0.kind == .folder })

        try await client.deleteItem(at: "/config/\(renamed)", profile: profile, session: session)
        let existsAfterDelete = try await client.itemExists(at: "/config/\(renamed)", profile: profile, session: session)
        XCTAssertFalse(existsAfterDelete)
        try await client.disconnect(session: session)
    }

    func testNativeSwiftPrivateKeySFTPListsWhenHarnessEnabled() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["DRIFTLINE_INTEGRATION_SFTP"] == "1" else {
            throw XCTSkip("Set DRIFTLINE_INTEGRATION_SFTP=1 after running scripts/integration-sftp-server.sh start")
        }

        let host = env["DRIFTLINE_TEST_HOST"] ?? "127.0.0.1"
        let port = Int(env["DRIFTLINE_TEST_PORT"] ?? "22222") ?? 22222
        let user = env["DRIFTLINE_TEST_USER"] ?? "driftline"
        let key = env["DRIFTLINE_TEST_KEY"] ?? ""
        guard !key.isEmpty else {
            throw XCTSkip("Set DRIFTLINE_TEST_KEY to the Docker harness private key.")
        }

        let profile = ServerProfile(
            displayName: "Native Key Integration",
            host: host,
            port: port,
            protocolKind: .sftp,
            username: user,
            authenticationMethod: .privateKey(path: key, passphrase: nil),
            remoteDefaultPath: "/config"
        )
        let trustStore = try await trustedStore(host: host, port: port)
        let client = NativeSFTPClient(credentialStore: InMemoryCredentialStore(), hostTrustStore: trustStore)
        let session = try await client.connect(to: profile)

        _ = try await client.listDirectory(at: "/config", profile: profile, session: session, preferences: FileListPreferences(showHiddenFiles: true))
        try await client.disconnect(session: session)
    }

    func testNativeSwiftTransferUploadDownloadWhenHarnessEnabled() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["DRIFTLINE_NATIVE_INTEGRATION_SFTP"] == "1" else {
            throw XCTSkip("Set DRIFTLINE_TEST_PASSWORD and DRIFTLINE_NATIVE_INTEGRATION_SFTP=1 before running scripts/integration-sftp-server.sh start")
        }
        guard let password = env["DRIFTLINE_TEST_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Native Swift transfer integration currently validates password auth; set DRIFTLINE_TEST_PASSWORD.")
        }

        let host = env["DRIFTLINE_TEST_HOST"] ?? "127.0.0.1"
        let port = Int(env["DRIFTLINE_TEST_PORT"] ?? "22222") ?? 22222
        let user = env["DRIFTLINE_TEST_USER"] ?? "driftline"
        let reference = CredentialReference(service: "app.driftline.integration", account: "transfer-\(user)@\(host)")
        let credentials = InMemoryCredentialStore()
        try await credentials.saveString(password, reference: reference)
        let trustStore = try await trustedStore(host: host, port: port)
        let profile = ServerProfile(
            displayName: "Native Transfer Integration",
            host: host,
            port: port,
            protocolKind: .sftp,
            username: user,
            authenticationMethod: .password(reference),
            remoteDefaultPath: "/config"
        )

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("driftline-native-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let uploadURL = temp.appendingPathComponent("upload.txt")
        let downloadURL = temp.appendingPathComponent("download.txt")
        let body = "native transfer \(UUID().uuidString)\n"
        try body.write(to: uploadURL, atomically: true, encoding: .utf8)

        let remotePath = "/config/driftline-transfer-\(UUID().uuidString).txt"
        let transferClient = NativeSFTPTransferClient(credentialStore: credentials, hostTrustStore: trustStore)
        let upload = TransferJob(direction: .upload, sourcePath: uploadURL.path, destinationPath: remotePath, byteCount: Int64(body.utf8.count), serverName: profile.displayName, protocolKind: .sftp)
        let progressRecorder = TransferProgressRecorder()
        try await transferClient.enqueue(upload, profile: profile) { updated in
            if case .running(let progress, _) = updated.status {
                await progressRecorder.append(progress)
            }
        }
        let uploadProgress = await progressRecorder.values()
        XCTAssertTrue(uploadProgress.contains { $0 > 0 })

        let download = TransferJob(direction: .download, sourcePath: remotePath, destinationPath: downloadURL.path, byteCount: Int64(body.utf8.count), serverName: profile.displayName, protocolKind: .sftp)
        try await transferClient.enqueue(download, profile: profile)
        XCTAssertEqual(try String(contentsOf: downloadURL, encoding: .utf8), body)

        let cleanupClient = NativeSFTPClient(credentialStore: credentials, hostTrustStore: trustStore)
        let session = try await cleanupClient.connect(to: profile)
        try await cleanupClient.deleteItem(at: remotePath, profile: profile, session: session)
        try await cleanupClient.disconnect(session: session)
    }

    func testNativeSwiftUploadCancellationClosesBeforeWritingWhenHarnessEnabled() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["DRIFTLINE_NATIVE_INTEGRATION_SFTP"] == "1" else {
            throw XCTSkip("Set DRIFTLINE_TEST_PASSWORD and DRIFTLINE_NATIVE_INTEGRATION_SFTP=1 before running scripts/integration-sftp-server.sh start")
        }
        guard let password = env["DRIFTLINE_TEST_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Native Swift transfer integration currently validates password auth; set DRIFTLINE_TEST_PASSWORD.")
        }

        let host = env["DRIFTLINE_TEST_HOST"] ?? "127.0.0.1"
        let port = Int(env["DRIFTLINE_TEST_PORT"] ?? "22222") ?? 22222
        let user = env["DRIFTLINE_TEST_USER"] ?? "driftline"
        let reference = CredentialReference(service: "app.driftline.integration", account: "cancel-\(user)@\(host)")
        let credentials = InMemoryCredentialStore()
        try await credentials.saveString(password, reference: reference)
        let trustStore = try await trustedStore(host: host, port: port)
        let profile = ServerProfile(
            displayName: "Native Cancel Integration",
            host: host,
            port: port,
            protocolKind: .sftp,
            username: user,
            authenticationMethod: .password(reference),
            remoteDefaultPath: "/config"
        )

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("driftline-native-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let uploadURL = temp.appendingPathComponent("cancel.txt")
        try String(repeating: "cancel\n", count: 1024).write(to: uploadURL, atomically: true, encoding: .utf8)

        let connection = try await NativeSFTPClient.makeConnection(profile: profile, credentialStore: credentials, hostTrustStore: trustStore)

        do {
            try await connection.uploadFile(
                localPath: uploadURL.path,
                remotePath: "/config/driftline-cancel-\(UUID().uuidString).txt",
                jobID: TransferJobID(),
                onProgress: { _, _ in },
                cancellation: { true }
            )
            XCTFail("Expected native upload cancellation to throw.")
        } catch is CancellationError {
            XCTAssertTrue(true)
        }
        await connection.close()
    }

    private func trustedStore(host: String, port: Int) async throws -> InMemoryHostTrustStore {
        let trustStore = InMemoryHostTrustStore()
        let fingerprint = try await SystemHostFingerprintProvider().fingerprint(host: host, port: port)
        try await trustStore.trust(HostTrustRecord(
            host: host,
            port: port,
            algorithm: fingerprint.algorithm,
            fingerprint: fingerprint.fingerprint,
            knownHostsLine: fingerprint.knownHostsLine
        ))
        return trustStore
    }
}

private actor TransferProgressRecorder {
    private var progress: [Double] = []

    func append(_ value: Double) {
        progress.append(value)
    }

    func values() -> [Double] {
        progress
    }
}
