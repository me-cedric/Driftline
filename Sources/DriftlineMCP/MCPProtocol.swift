import Foundation

// MARK: - Protocol Version Negotiation

public enum MCPProtocolVersion {
    public static let current = "2025-11-25"
    public static let supported: Set = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    /// Echo the client's version if recognised, else advertise `current`.
    public static func negotiate(clientRequested: String?) -> String {
        guard let clientRequested else { return self.current }
        return self.supported.contains(clientRequested) ? clientRequested : self.current
    }
}

// MARK: - Initialize params

public struct MCPInitializeParams: Sendable {
    public let protocolVersion: String
    public let capabilities: JSONValue?
    public let clientInfo: JSONValue?

    /// Parse from the JSON-RPC params object.
    /// Returns nil if `protocolVersion` is missing or not a string (→ caller should reply -32602).
    public init?(params: JSONValue?) {
        guard let params else { return nil }
        guard let versionStr = params["protocolVersion"]?.stringValue else { return nil }
        self.protocolVersion = versionStr
        self.capabilities = params["capabilities"]
        self.clientInfo = params["clientInfo"]
    }
}

// MARK: - Server info

public enum MCPServerInfo {
    public static let name = "Driftline MCP"
    public static let title = "Driftline SFTP"
    public static let version = "0.6.0"

    static var asJSON: JSONValue {
        .object([
            "name": .string(name),
            "title": .string(title),
            "version": .string(version),
        ])
    }
}

// MARK: - MCPTool descriptor

/// Describes a single MCP tool for tools/list responses.
public struct MCPToolDescriptor: Sendable {
    public let name: String
    public let title: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, title: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
    }

    /// Serialised form expected by tools/list.
    public var asJSON: JSONValue {
        .object([
            "name": .string(self.name),
            "title": .string(self.title),
            "description": .string(self.description),
            "inputSchema": self.inputSchema,
        ])
    }
}

// MARK: - CallToolResult

/// The result of a tool call – always returned as a successful JSON-RPC response.
/// `isError: true` signals a tool-level failure (not a JSON-RPC error).
public struct CallToolResult: Sendable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }

    /// Compact JSON payload for the text content item.
    public var contentItem: JSONValue {
        .object(["type": .string("text"), "text": .string(self.text)])
    }

    /// Full JSON-RPC result value.
    public var resultJSON: JSONValue {
        .object([
            "content": .array([self.contentItem]),
            "isError": .bool(self.isError),
        ])
    }

    // MARK: Static factories

    /// Build a success result from an Encodable payload.
    public static func success(_ payload: JSONValue) -> CallToolResult {
        let text = (try? JSONValueEncoder.encodeToString(payload)) ?? "{}"
        return CallToolResult(text: text, isError: false)
    }

    /// Build an error result from a structured error payload.
    public static func toolError(code: String, message: String, data: JSONValue = .object([:])) -> CallToolResult {
        let payload = JSONValue.object([
            "error": .object([
                "code": .string(code),
                "message": .string(message),
                "data": data,
            ]),
        ])
        let text = (try? JSONValueEncoder.encodeToString(payload)) ?? "{}"
        return CallToolResult(text: text, isError: true)
    }
}

// MARK: - Tool error codes (machine-readable)

public enum MCPToolErrorCode {
    public static let hostNotTrusted = "host_not_trusted"
    public static let hostFingerprintChanged = "host_fingerprint_changed"
    public static let authenticationFailed = "authentication_failed"
    public static let itemAlreadyExists = "item_already_exists"
    public static let connectionFailed = "connection_failed"
    public static let commandFailed = "command_failed"
    public static let unsupported = "unsupported"
    public static let capabilityDenied = "capability_denied"
    public static let serverDisabled = "server_disabled"
    public static let pathNotAllowed = "path_not_allowed"
    public static let authUnavailableStandalone = "auth_unavailable_standalone"
    public static let notFound = "not_found"
    public static let invalidArguments = "invalid_arguments"
}

// MARK: - Process kind

/// Indicates whether the engine is running inside the app or the standalone binary.
public enum MCPProcessKind: Sendable {
    case standalone
    case embedded
}
