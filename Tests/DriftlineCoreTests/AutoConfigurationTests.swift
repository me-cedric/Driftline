@testable import DriftlineApp
@testable import DriftlineCore
import XCTest

final class AutoConfigurationTests: XCTestCase {
    private let profile = ServerProfile(displayName: "S", host: "sftp.example.com", protocolKind: .sftp, username: "u", authenticationMethod: .password(CredentialReference(service: "s", account: "a")))

    // MARK: Native to System SSH fallback

    func testUnsupportedNativeServerFallsBackToSystemSSH() async throws {
        let native = StubRemoteClient(connectError: .nativeBackendUnavailable("RSA-only host key"))
        let system = StubRemoteClient()
        let client = BackendFallbackRemoteFileSystemClient(native: native, system: system, registry: NativeSSHSupportRegistry())

        let session = try await client.connect(to: self.profile)
        _ = try await client.listDirectory(at: "/", profile: self.profile, session: session, preferences: FileListPreferences())
        _ = try await client.connect(to: self.profile)

        XCTAssertEqual(session.fallbackBackend, .systemSSH)
        let nativeConnects = await native.connects
        let systemLists = await system.lists
        XCTAssertEqual(nativeConnects, 1, "The second connect goes straight to System SSH")
        XCTAssertEqual(systemLists, 1)
    }

    func testWrongPasswordAndHostKeyErrorsNeverFallBack() async {
        for error in [RemoteClientError.authenticationFailed, .hostFingerprintChanged] {
            let system = StubRemoteClient()
            let client = BackendFallbackRemoteFileSystemClient(native: StubRemoteClient(connectError: error), system: system, registry: NativeSSHSupportRegistry())
            do {
                _ = try await client.connect(to: self.profile)
                XCTFail("Expected \(error)")
            } catch {
                let systemConnects = await system.connects
                XCTAssertEqual(systemConnects, 0)
            }
        }
    }

    func testAgentLoginSkipsNativeSSH() async throws {
        var agentProfile = self.profile
        agentProfile.authenticationMethod = .agent
        let native = StubRemoteClient()
        let client = BackendFallbackRemoteFileSystemClient(native: native, system: StubRemoteClient(), registry: NativeSSHSupportRegistry())

        let session = try await client.connect(to: agentProfile)

        XCTAssertEqual(session.fallbackBackend, .systemSSH)
        let nativeConnects = await native.connects
        XCTAssertEqual(nativeConnects, 0)
    }

    // MARK: Probe parsing

    func testSSHDebugGivesLoginMethodsAndNativeSupport() {
        let modern = """
        debug2: local client KEXINIT proposal
        debug2: KEX algorithms: sntrup761x25519-sha512
        debug2: peer server KEXINIT proposal
        debug2: KEX algorithms: curve448-sha512,curve25519-sha256,diffie-hellman-group14-sha256
        debug2: host key algorithms: ssh-ed448,ssh-ed25519,rsa-sha2-512
        debug2: ciphers ctos: chacha20-poly1305@openssh.com,aes256-ctr
        debug2: ciphers stoc: chacha20-poly1305@openssh.com,aes256-ctr
        debug2: MACs ctos: hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
        debug2: MACs stoc: hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
        debug2: first_kex_follows 0
        debug1: Authentications that can continue: publickey,password
        """
        let legacy = modern.replacingOccurrences(of: "ssh-ed448,ssh-ed25519,rsa-sha2-512", with: "rsa-sha2-512,ssh-rsa")

        XCTAssertEqual(SystemServerProbe.parseSSHDebug(modern), .init(methods: ["publickey", "password"], nativeSupported: true))
        XCTAssertEqual(SystemServerProbe.parseSSHDebug(legacy).nativeSupported, false)
    }

    func testSSHConfigAliasGivesHostUserAndPort() {
        let output = "user deploy\nhostname files.example.com\nport 2222\nidentityfile ~/.ssh/does-not-exist\nproxyjump none\n"

        let config = SystemServerProbe.parseSSHConfig(output, host: "files", localUser: "me")

        XCTAssertEqual(config, .init(hostName: "files.example.com", user: "deploy", port: 2222, identityFiles: []))
        XCTAssertNil(SystemServerProbe.parseSSHConfig(output + "proxyjump bastion\n", host: "files", localUser: "me").hostName)
    }

    func testLoginSuggestionPrefersLoadedKeysThenPassword() async {
        let withKeys = SystemServerProbe(identities: StubIdentities(count: 2))
        let withoutKeys = SystemServerProbe(identities: StubIdentities(count: 0))

        let keyed = await withKeys.suggestion(methods: ["publickey", "password"], identityFiles: [])
        let password = await withoutKeys.suggestion(methods: ["publickey", "password"], identityFiles: ["/k"])
        let keyFile = await withoutKeys.suggestion(methods: ["publickey"], identityFiles: ["/k"])
        XCTAssertEqual(keyed, .agent)
        XCTAssertEqual(password, .password)
        XCTAssertEqual(keyFile, .privateKey(path: "/k"))
    }

    func testPortProbeRecognisesSSHAndFTPGreetings() throws {
        // Real servers send key exchange bytes right after the banner, and long multi-line FTP greetings.
        let ssh = try LocalGreetingServer(greeting: Data("SSH-2.0-OpenSSH_9.9\r\n".utf8) + Data([0, 0, 2, 0xfc, 0x0b, 0x14]))
        let ftp = try LocalGreetingServer(greeting: Data("220-Welcome\r\n Authorised users only\r\n220 Ready\r\n".utf8), reply: "234 Proceed\r\n")

        XCTAssertEqual(SystemServerProbe.probePort(host: "127.0.0.1", port: ssh.port, timeout: 2), .ssh("SSH-2.0-OpenSSH_9.9"))
        XCTAssertEqual(SystemServerProbe.probePort(host: "127.0.0.1", port: ftp.port, timeout: 2), .ftp("Welcome", explicitTLS: true))
    }

    // MARK: Editor and connection fixes

    func testNewDraftTakesDetectionOnlyForUntouchedFields() {
        var draft = ServerProfileDraft()
        draft.host = "files.example.com"
        draft.portEdited = true
        draft.port = 2121
        let detection = ServerDetection(host: "files.example.com", protocolKind: .ftps, port: 21, implicitTLS: false, suggestedAuthentication: .password)

        draft.apply(detection, force: false)

        XCTAssertEqual(draft.protocolKind, .ftps)
        XCTAssertEqual(draft.port, 2121)
        XCTAssertFalse(draft.ftpsImplicitTLS)
        XCTAssertEqual(draft.authKind, .password)
    }

    func testConnectionFixProposesOnlyRealDifferences() {
        let ftps = ServerDetection(host: "sftp.example.com", protocolKind: .ftps, port: 21, implicitTLS: false, suggestedAuthentication: .password)
        let sftpKeys = ServerDetection(host: "sftp.example.com", protocolKind: .sftp, port: 22, authenticationMethods: ["publickey", "password"], suggestedAuthentication: .agent)
        var agentProfile = self.profile
        agentProfile.authenticationMethod = .agent

        XCTAssertNotNil(ConnectionFix(profile: self.profile, detection: ftps, authenticationFailed: false))
        XCTAssertNil(ConnectionFix(profile: self.profile, detection: sftpKeys, authenticationFailed: true), "A wrong password is not a settings problem")
        XCTAssertNil(ConnectionFix(profile: agentProfile, detection: sftpKeys, authenticationFailed: true, agentHasKeys: true))
        XCTAssertEqual(ConnectionFix(profile: agentProfile, detection: sftpKeys, authenticationFailed: true, agentHasKeys: false)?.changesAuthentication, true)
    }

    func testConnectionFixNeverProposesPlainFTPForAnEncryptedProfile() {
        let plain = ServerDetection(host: "sftp.example.com", protocolKind: .ftp, port: 21, suggestedAuthentication: .password)

        XCTAssertNil(ConnectionFix(profile: self.profile, detection: plain, authenticationFailed: false))
    }

    func testDetectionOfAnotherProtocolLeavesPortAndLoginAlone() {
        var draft = ServerProfileDraft()
        draft.changeProtocol(to: .ftp)
        draft.protocolEdited = true
        draft.authKind = .none

        draft.apply(ServerDetection(host: "h", protocolKind: .sftp, port: 22, suggestedAuthentication: .agent), force: false)

        XCTAssertEqual(draft.protocolKind, .ftp)
        XCTAssertEqual(draft.port, 21)
        XCTAssertEqual(draft.authKind, .none)
    }

    func testAddressOnlyFixKeepsTheLoginMethod() {
        var draft = ServerProfileDraft()
        draft.authKind = .privateKey

        draft.apply(ServerDetection(host: "h", protocolKind: .sftp, port: 2222, suggestedAuthentication: .agent), force: true, includeAuthentication: false)

        XCTAssertEqual(draft.port, 2222)
        XCTAssertEqual(draft.authKind, .privateKey)
    }

    func testSSHDebugStopsAtTheEndOfTheServerProposal() {
        let output = """
        debug2: peer server KEXINIT proposal
        debug2: KEX algorithms: curve25519-sha256
        debug2: first_kex_follows 0
        debug2: host key algorithms: ssh-ed25519
        """

        XCTAssertEqual(SystemServerProbe.parseSSHDebug(output).nativeSupported, false)
    }

    func testCancelledCallerStopsItsProcess() async throws {
        let started = Date()
        let task = Task { try await FoundationProcessExecutor().run(executable: "/bin/sleep", arguments: ["5"], timeout: 30) }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        _ = try? await task.value

        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }
}

private actor StubRemoteClient: RemoteFileSystemClient {
    private let connectError: RemoteClientError?
    private(set) var connects = 0
    private(set) var lists = 0

    init(connectError: RemoteClientError? = nil) {
        self.connectError = connectError
    }

    func connect(to profile: ServerProfile) async throws -> ConnectionSession {
        self.connects += 1
        if let connectError { throw connectError }
        return ConnectionSession(serverID: profile.id, state: .connected, protocolKind: profile.protocolKind)
    }

    func disconnect(session _: ConnectionSession) async throws {}

    func listDirectory(at _: String, profile _: ServerProfile, session _: ConnectionSession, preferences _: FileListPreferences) async throws -> [FileItem] {
        self.lists += 1
        return []
    }

    func createFolder(named _: String, in _: String, profile _: ServerProfile, session _: ConnectionSession) async throws {}
    func renameItem(at _: String, to _: String, profile _: ServerProfile, session _: ConnectionSession) async throws {}
    func deleteItem(at _: String, profile _: ServerProfile, session _: ConnectionSession) async throws {}
    func itemExists(at _: String, profile _: ServerProfile, session _: ConnectionSession) async throws -> Bool {
        false
    }
}

private struct StubIdentities: SSHIdentityInventory {
    var count: Int

    func agentIdentityCount() async -> Int {
        self.count
    }
}

/// A one-shot TCP server on 127.0.0.1 that sends a greeting and answers the first line.
private final class LocalGreetingServer: @unchecked Sendable {
    let port: Int
    private let descriptor: Int32

    init(greeting: Data, reply: String? = nil) throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, length) } }
        guard bound == 0, listen(listener, 1) == 0 else { throw RemoteClientError.connectionFailed("listen") }
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) } }
        self.descriptor = listener
        self.port = Int(UInt16(bigEndian: address.sin_port))
        Thread {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            _ = greeting.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
            if let reply {
                var buffer = [UInt8](repeating: 0, count: 256)
                _ = read(client, &buffer, buffer.count)
                _ = reply.withCString { write(client, $0, strlen($0)) }
            }
            usleep(200_000)
            close(client)
        }.start()
    }

    deinit {
        close(self.descriptor)
    }
}
