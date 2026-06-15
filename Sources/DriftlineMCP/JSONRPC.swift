import Foundation

// MARK: - JSON-RPC Error Codes

public enum JSONRPCCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

// MARK: - JSONRPCRequest

/// Decoded view of an incoming JSON-RPC 2.0 request or notification.
public struct JSONRPCRequest: Sendable {
    /// The id is nil for notifications (no id key, or explicit null treated as notification).
    public let id: JSONValue?
    public let method: String
    public let params: JSONValue?

    /// Whether this is a notification (no id — must never reply).
    public var isNotification: Bool {
        self.id == nil
    }

    public init(id: JSONValue?, method: String, params: JSONValue?) {
        self.id = id
        self.method = method
        self.params = params
    }
}

// MARK: - JSONRPCResponse builders

/// Helpers for building JSON-RPC 2.0 response objects as JSONValue.
public enum JSONRPCResponse {
    /// Build a successful result response.
    public static func result(id: JSONValue, result: JSONValue) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "result": result,
        ])
    }

    /// Build an error response.
    public static func error(id: JSONValue, code: Int, message: String, data: JSONValue? = nil) -> JSONValue {
        var errorObj: [String: JSONValue] = [
            "code": .number(Double(code)),
            "message": .string(message),
        ]
        if let data {
            errorObj["data"] = data
        }
        return .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "error": .object(errorObj),
        ])
    }

    // MARK: Convenience shorthands

    public static func parseError(id: JSONValue = .null) -> JSONValue {
        self.error(id: id, code: JSONRPCCode.parseError, message: "Parse error")
    }

    public static func invalidRequest(id: JSONValue = .null, detail: String = "Invalid Request") -> JSONValue {
        self.error(id: id, code: JSONRPCCode.invalidRequest, message: detail)
    }

    public static func methodNotFound(id: JSONValue, method: String) -> JSONValue {
        self.error(id: id, code: JSONRPCCode.methodNotFound, message: "Method not found: \(method)")
    }

    public static func invalidParams(id: JSONValue, detail: String) -> JSONValue {
        self.error(id: id, code: JSONRPCCode.invalidParams, message: detail)
    }

    public static func internalError(id: JSONValue, detail: String) -> JSONValue {
        self.error(id: id, code: JSONRPCCode.internalError, message: "Internal error: \(detail)")
    }
}

// MARK: - Parsing

/// Parse result — using a bespoke enum because JSONValue cannot conform to Error.
public enum JSONRPCParseResult: Sendable {
    case success(JSONRPCRequest)
    case failure(JSONValue) // contains a ready-to-send error response
}

public extension JSONRPCRequest {
    /// Parse a decoded JSONValue into a JSONRPCRequest, or return an error response JSONValue.
    static func parse(from value: JSONValue) -> JSONRPCParseResult {
        guard case let .object(obj) = value else {
            return .failure(JSONRPCResponse.invalidRequest())
        }
        // Validate jsonrpc field
        guard let ver = obj["jsonrpc"], ver == .string("2.0") else {
            return .failure(JSONRPCResponse.invalidRequest())
        }
        // method must be a string
        guard let methodVal = obj["method"], case let .string(method) = methodVal, !method.isEmpty else {
            return .failure(JSONRPCResponse.invalidRequest())
        }
        // id is optional; if absent this is a notification
        let id = obj["id"]
        let params = obj["params"]
        return .success(JSONRPCRequest(id: id, method: method, params: params))
    }
}
