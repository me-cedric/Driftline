import DriftlineCore
import DriftlineMCP
import Foundation
import Testing

@Suite("DriftlineMCP")
struct DriftlineMCPTests {
    @Test func initializeAndListTools() async {
        let engine = makeEngine(config: MCPServerConfiguration(enabled: true))

        let initialized = await engine.handle(.object([
            "jsonrpc": .string("2.0"),
            "id": .int(1),
            "method": .string("initialize"),
            "params": .object([
                "protocolVersion": .string(MCPProtocolVersion.current),
                "capabilities": .object([:]),
                "clientInfo": .object(["name": .string("test"), "version": .string("1")]),
            ]),
        ]))

        #expect(initialized?["result"]?["protocolVersion"] == .string(MCPProtocolVersion.current))
        #expect(initialized?["result"]?["capabilities"]?["tools"] != nil)

        let notification = await engine.handle(.object([
            "jsonrpc": .string("2.0"),
            "method": .string("notifications/initialized"),
        ]))
        #expect(notification == nil)

        let tools = await engine.handle(.object([
            "jsonrpc": .string("2.0"),
            "id": .int(2),
            "method": .string("tools/list"),
        ]))
        let names = tools?["result"]?["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        #expect(names.contains("driftline.listProfiles"))
        #expect(names.contains("driftline.getProfile"))
        #expect(names.contains("driftline.listLocal"))
    }

    @Test func disabledServerReturnsToolError() async throws {
        let engine = await initializedEngine(config: MCPServerConfiguration(enabled: false))
        let response = await callTool(engine, name: "driftline.listProfiles", arguments: .object([:]))
        let payload = try toolPayload(response)
        #expect(response?["result"]?["isError"] == .bool(true))
        #expect(payload["error"]?["code"] == .string(MCPToolErrorCode.serverDisabled))
    }

    @Test func listProfilesDoesNotExposeSecretReferences() async {
        let profile = testProfile(authenticationMethod: .password(CredentialReference(service: "secret-service", account: "secret-account")))
        let engine = await initializedEngine(
            config: MCPServerConfiguration(enabled: true),
            profiles: [profile]
        )

        let response = await callTool(engine, name: "driftline.listProfiles", arguments: .object([:]))
        let text = response?["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
        #expect(text.contains(profile.id.rawValue.uuidString))
        #expect(text.contains("password"))
        #expect(!text.contains("secret-service"))
        #expect(!text.contains("secret-account"))
    }

    @Test func localSandboxDeniesOutsideRoots() async throws {
        let root = temporaryDirectory("mcp-allowed")
        let outside = temporaryDirectory("mcp-outside").appendingPathComponent("nope").path
        let engine = await initializedEngine(
            config: MCPServerConfiguration(enabled: true, allowedLocalRoots: [root.path])
        )

        let response = await callTool(
            engine,
            name: "driftline.listLocal",
            arguments: .object(["path": .string(outside)])
        )
        let payload = try toolPayload(response)
        #expect(response?["result"]?["isError"] == .bool(true))
        #expect(payload["error"]?["code"] == .string(MCPToolErrorCode.pathNotAllowed))
    }

    @Test func uploadOverwriteRequiresDestructiveFlag() async throws {
        let root = temporaryDirectory("mcp-upload")
        let localFile = root.appendingPathComponent("upload.txt")
        try "hello".write(to: localFile, atomically: true, encoding: .utf8)

        let remote = MockRemoteFileSystemClient(remoteExists: true)
        let registry = MCPSessionRegistry()
        let profile = testProfile()
        let session = ConnectionSession(state: .connected, protocolKind: .sftp)
        await registry.register(session: session, profile: profile)
        let engine = await initializedEngine(
            config: MCPServerConfiguration(enabled: true, allowedLocalRoots: [root.path]),
            profiles: [profile],
            remoteFileSystem: remote,
            sessionRegistry: registry
        )

        let response = await callTool(engine, name: "driftline.upload", arguments: .object([
            "sessionId": .string(session.id.uuidString),
            "localPath": .string(localFile.path),
            "remotePath": .string("/upload.txt"),
            "overwrite": .bool(true),
        ]))
        let payload = try toolPayload(response)
        #expect(payload["error"]?["code"] == .string(MCPToolErrorCode.capabilityDenied))
    }

    @Test func deleteRequiresDestructiveFlag() async throws {
        let engine = await initializedEngine(config: MCPServerConfiguration(enabled: true))
        let response = await callTool(engine, name: "driftline.delete", arguments: .object([
            "sessionId": .string(UUID().uuidString),
            "path": .string("/danger"),
        ]))
        let payload = try toolPayload(response)
        #expect(payload["error"]?["code"] == .string(MCPToolErrorCode.capabilityDenied))
    }

    @Test func httpTransportRequiresAuthAndKeepsInitializedState() async throws {
        let token = "test-token"
        let server = HTTPMCPServer(
            server: MCPServer(context: makeContext(config: MCPServerConfiguration(enabled: true))),
            port: 0,
            bearerToken: token
        )
        try await server.start()
        guard let port = await server.localPort() else {
            Issue.record("HTTP server did not expose a local port")
            return
        }

        let initializeMessage = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .int(1),
            "method": .string("initialize"),
            "params": .object([
                "protocolVersion": .string(MCPProtocolVersion.current),
                "capabilities": .object([:]),
                "clientInfo": .object(["name": .string("test"), "version": .string("1")]),
            ]),
        ])
        let unauthorized = try await postHTTP(port: port, token: nil, message: initializeMessage)
        #expect(unauthorized.statusCode == 401)

        let initialized = try await postHTTP(port: port, token: token, message: initializeMessage)
        #expect(initialized.statusCode == 200)
        #expect(try (JSONValueDecoder.decode(initialized.data))["result"]?["protocolVersion"] == .string(MCPProtocolVersion.current))

        let notification = try await postHTTP(port: port, token: token, message: .object([
            "jsonrpc": .string("2.0"),
            "method": .string("notifications/initialized"),
        ]))
        #expect(notification.statusCode == 202)

        let listed = try await postHTTP(port: port, token: token, message: .object([
            "jsonrpc": .string("2.0"),
            "id": .int(2),
            "method": .string("tools/list"),
        ]))
        let response = try JSONValueDecoder.decode(listed.data)
        let names = response["result"]?["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        #expect(names.contains("driftline.listProfiles"))

        await server.stop()
    }
}

private func initializedEngine(
    config: MCPServerConfiguration,
    profiles: [ServerProfile] = [],
    remoteFileSystem: any RemoteFileSystemClient = MockRemoteFileSystemClient(),
    sessionRegistry: MCPSessionRegistry = MCPSessionRegistry()
) async -> MCPEngine {
    let engine = makeEngine(
        config: config,
        profiles: profiles,
        remoteFileSystem: remoteFileSystem,
        sessionRegistry: sessionRegistry
    )
    _ = await engine.handle(.object([
        "jsonrpc": .string("2.0"),
        "id": .int(1),
        "method": .string("initialize"),
        "params": .object([
            "protocolVersion": .string(MCPProtocolVersion.current),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("test"), "version": .string("1")]),
        ]),
    ]))
    _ = await engine.handle(.object([
        "jsonrpc": .string("2.0"),
        "method": .string("notifications/initialized"),
    ]))
    return engine
}

private func makeEngine(
    config: MCPServerConfiguration,
    profiles: [ServerProfile] = [],
    remoteFileSystem: any RemoteFileSystemClient = MockRemoteFileSystemClient(),
    sessionRegistry: MCPSessionRegistry = MCPSessionRegistry()
) -> MCPEngine {
    MCPServer(context: makeContext(
        config: config,
        profiles: profiles,
        remoteFileSystem: remoteFileSystem,
        sessionRegistry: sessionRegistry
    )).makeEngine()
}

private func makeContext(
    config: MCPServerConfiguration,
    profiles: [ServerProfile] = [],
    remoteFileSystem: any RemoteFileSystemClient = MockRemoteFileSystemClient(),
    sessionRegistry: MCPSessionRegistry = MCPSessionRegistry()
) -> MCPToolContext {
    MCPToolContext(
        localFileSystem: MockLocalFileSystemClient(),
        remoteFileSystem: remoteFileSystem,
        transferClient: RecordingTransferClient(),
        profileRepository: InMemoryServerProfileRepository(profiles: profiles),
        hostTrustStore: InMemoryHostTrustStore(),
        sessionRegistry: sessionRegistry,
        sandbox: LocalPathSandbox(roots: config.allowedLocalRoots),
        configuration: config,
        processKind: .embedded
    )
}

private func callTool(_ engine: MCPEngine, name: String, arguments: JSONValue) async -> JSONValue? {
    await engine.handle(.object([
        "jsonrpc": .string("2.0"),
        "id": .int(99),
        "method": .string("tools/call"),
        "params": .object([
            "name": .string(name),
            "arguments": arguments,
        ]),
    ]))
}

private func toolPayload(_ response: JSONValue?) throws -> JSONValue {
    let text = response?["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue ?? "{}"
    return try JSONValueDecoder.decode(text)
}

private func testProfile(authenticationMethod: AuthenticationMethod = .agent) -> ServerProfile {
    ServerProfile(
        displayName: "Example",
        host: "example.test",
        protocolKind: .sftp,
        username: "alice",
        authenticationMethod: authenticationMethod
    )
}

private func temporaryDirectory(_ name: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func postHTTP(port: Int, token: String?, message: JSONValue) async throws -> (statusCode: Int, data: Data) {
    let url = URL(string: "http://127.0.0.1:\(port)/mcp")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    if let token {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = try JSONValueEncoder.encode(message)
    let (data, response) = try await URLSession.shared.data(for: request)
    let http = try #require(response as? HTTPURLResponse)
    return (http.statusCode, data)
}

private actor MockLocalFileSystemClient: LocalFileSystemClient {
    func listDirectory(at path: String, preferences _: FileListPreferences) async throws -> [FileItem] {
        [
            FileItem(name: "local.txt", path: (path as NSString).appendingPathComponent("local.txt"), kind: .file, source: .local),
        ]
    }

    func createFolder(named _: String, in _: String) async throws {}
    func renameItem(at _: String, to _: String) async throws {}
    func deleteItem(at _: String) async throws {}
    func itemExists(at _: String) async -> Bool {
        true
    }
}

private actor MockRemoteFileSystemClient: RemoteFileSystemClient {
    private let remoteExists: Bool

    init(remoteExists: Bool = false) {
        self.remoteExists = remoteExists
    }

    func connect(to profile: ServerProfile) async throws -> ConnectionSession {
        ConnectionSession(serverID: profile.id, state: .connected, protocolKind: profile.protocolKind)
    }

    func disconnect(session _: ConnectionSession) async throws {}

    func listDirectory(at path: String, profile _: ServerProfile, session _: ConnectionSession, preferences _: FileListPreferences) async throws -> [FileItem] {
        [
            FileItem(name: "remote.txt", path: (path as NSString).appendingPathComponent("remote.txt"), kind: .file, source: .remote),
        ]
    }

    func createFolder(named _: String, in _: String, profile _: ServerProfile, session _: ConnectionSession) async throws {}
    func renameItem(at _: String, to _: String, profile _: ServerProfile, session _: ConnectionSession) async throws {}
    func deleteItem(at _: String, profile _: ServerProfile, session _: ConnectionSession) async throws {}
    func itemExists(at _: String, profile _: ServerProfile, session _: ConnectionSession) async throws -> Bool {
        self.remoteExists
    }
}

private actor RecordingTransferClient: TransferClient {
    private var recordedJobs: [TransferJob] = []

    func enqueue(_ job: TransferJob, profile _: ServerProfile, onUpdate _: (@Sendable (TransferJob) async -> Void)?) async throws {
        self.recordedJobs.append(job)
    }

    func cancel(id _: TransferJobID) async throws {}
    func retry(id _: TransferJobID) async throws {}
    func jobs() async -> [TransferJob] {
        self.recordedJobs
    }
}
