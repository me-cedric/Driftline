import DriftlineCore
import Foundation

// MARK: - MCPToolContext

/// Sendable bag of collaborators passed to every tool handler.
public struct MCPToolContext: Sendable {
    public let localFileSystem: any LocalFileSystemClient
    public let remoteFileSystem: any RemoteFileSystemClient
    public let transferClient: any TransferClient
    public let profileRepository: any ServerProfileRepository
    public let hostTrustStore: any HostTrustStore
    public let sessionRegistry: MCPSessionRegistry
    public let sandbox: LocalPathSandbox
    public let configuration: MCPServerConfiguration
    public let processKind: MCPProcessKind

    public init(
        localFileSystem: any LocalFileSystemClient,
        remoteFileSystem: any RemoteFileSystemClient,
        transferClient: any TransferClient,
        profileRepository: any ServerProfileRepository,
        hostTrustStore: any HostTrustStore,
        sessionRegistry: MCPSessionRegistry,
        sandbox: LocalPathSandbox,
        configuration: MCPServerConfiguration,
        processKind: MCPProcessKind
    ) {
        self.localFileSystem = localFileSystem
        self.remoteFileSystem = remoteFileSystem
        self.transferClient = transferClient
        self.profileRepository = profileRepository
        self.hostTrustStore = hostTrustStore
        self.sessionRegistry = sessionRegistry
        self.sandbox = sandbox
        self.configuration = configuration
        self.processKind = processKind
    }
}

// MARK: - MCPEngine

/// Per-connection actor that handles MCP handshake state and dispatches requests.
public actor MCPEngine {
    private var initialized = false
    private var negotiatedVersion: String = MCPProtocolVersion.current
    private let context: MCPToolContext

    public init(context: MCPToolContext) {
        self.context = context
    }

    // MARK: Entry point

    /// Handle one decoded JSON-RPC message. Returns the response (nil for notifications).
    public func handle(_ message: JSONValue) async -> JSONValue? {
        switch JSONRPCRequest.parse(from: message) {
        case let .failure(errorResponse):
            errorResponse
        case let .success(request):
            await self.dispatch(request)
        }
    }

    // MARK: Dispatch

    private func dispatch(_ request: JSONRPCRequest) async -> JSONValue? {
        let id = request.id ?? .null

        // Notifications never get responses.
        if request.isNotification {
            self.handleNotification(request)
            return nil
        }

        // Guard: certain methods are allowed pre-init; all others require init first.
        switch request.method {
        case "initialize":
            return self.handleInitialize(id: id, params: request.params)
        case "ping":
            return self.handlePing(id: id)
        default:
            if !self.initialized {
                return JSONRPCResponse.invalidRequest(
                    id: id,
                    detail: "Server not initialized"
                )
            }
            return await self.handleMethod(request.method, id: id, params: request.params)
        }
    }

    // MARK: Pre-init methods

    private func handleInitialize(id: JSONValue, params: JSONValue?) -> JSONValue {
        // protocolVersion must be present and a string.
        guard let params, let versionStr = params["protocolVersion"]?.stringValue else {
            let supported = MCPProtocolVersion.supported.sorted()
            return JSONRPCResponse.error(
                id: id,
                code: JSONRPCCode.invalidParams,
                message: "Unsupported protocol version",
                data: .object([
                    "supported": .array(supported.map { .string($0) }),
                    "requested": params?["protocolVersion"] ?? .null,
                ])
            )
        }
        let negotiated = MCPProtocolVersion.negotiate(clientRequested: versionStr)
        self.negotiatedVersion = negotiated

        let result = JSONValue.object([
            "protocolVersion": .string(negotiated),
            "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
            "serverInfo": MCPServerInfo.asJSON,
        ])
        return JSONRPCResponse.result(id: id, result: result)
    }

    private func handlePing(id: JSONValue) -> JSONValue {
        JSONRPCResponse.result(id: id, result: .object([:]))
    }

    // MARK: Notification handling

    private func handleNotification(_ request: JSONRPCRequest) {
        switch request.method {
        case "notifications/initialized":
            self.initialized = true
        default:
            // All other notifications silently ignored.
            break
        }
    }

    // MARK: Post-init methods

    private func handleMethod(_ method: String, id: JSONValue, params: JSONValue?) async -> JSONValue {
        switch method {
        case "tools/list":
            return self.handleToolsList(id: id)
        case "tools/call":
            return await self.handleToolsCall(id: id, params: params)
        default:
            // Silently ignore any other notification-style paths.
            if method.hasPrefix("notifications/") {
                return JSONRPCResponse.invalidRequest(id: id, detail: "Unexpected notification after init")
            }
            return JSONRPCResponse.methodNotFound(id: id, method: method)
        }
    }

    private func handleToolsList(id: JSONValue) -> JSONValue {
        let tools = MCPToolCatalog.all.map(\.asJSON)
        return JSONRPCResponse.result(id: id, result: .object(["tools": .array(tools)]))
    }

    private func handleToolsCall(id: JSONValue, params: JSONValue?) async -> JSONValue {
        // params must be an object
        guard case .object = params else {
            return JSONRPCResponse.invalidParams(id: id, detail: "params must be an object")
        }
        // name must be a string
        guard let toolName = params?["name"]?.stringValue, !toolName.isEmpty else {
            return JSONRPCResponse.invalidParams(id: id, detail: "params.name is required and must be a string")
        }
        let arguments = params?["arguments"] ?? .object([:])

        // Server disabled guard: return a server_disabled tool error (not a JSON-RPC error).
        guard self.context.configuration.enabled else {
            let result = CallToolResult.toolError(
                code: MCPToolErrorCode.serverDisabled,
                message: "MCP server is disabled. Enable it in Driftline > Settings > MCP."
            )
            return JSONRPCResponse.result(id: id, result: result.resultJSON)
        }

        let toolResult = await MCPToolRouter.call(
            name: toolName,
            arguments: arguments,
            context: self.context
        )
        return JSONRPCResponse.result(id: id, result: toolResult.resultJSON)
    }
}

// MARK: - MCPServer

/// Lightweight façade that owns the context and starts/stops transports.
public struct MCPServer: Sendable {
    public let context: MCPToolContext

    public init(context: MCPToolContext) {
        self.context = context
    }

    /// Create a fresh engine per connection (each transport connection is independent).
    public func makeEngine() -> MCPEngine {
        MCPEngine(context: self.context)
    }
}
