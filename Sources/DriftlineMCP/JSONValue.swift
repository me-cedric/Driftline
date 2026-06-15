import Foundation

// MARK: - JSONValue

/// Minimal recursive JSON value enum — avoids `Any`, is Sendable and Codable.
/// JSON-RPC ids, params, and results all use this type.
public indirect enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let b = try? single.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? single.decode(Double.self) {
            self = .number(n)
        } else if let s = try? single.decode(String.self) {
            self = .string(s)
        } else if let a = try? single.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? single.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown JSON value")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .null:
            try single.encodeNil()
        case let .bool(b):
            try single.encode(b)
        case let .number(n):
            // Encode as integer when the value is exact.
            if n == n.rounded(), n >= Double(Int.min), n <= Double(Int.max) {
                try single.encode(Int(n))
            } else {
                try single.encode(n)
            }
        case let .string(s):
            try single.encode(s)
        case let .array(a):
            try single.encode(a)
        case let .object(o):
            try single.encode(o)
        }
    }
}

// MARK: - Ergonomic accessors

public extension JSONValue {
    var stringValue: String? {
        guard case let .string(s) = self else { return nil }
        return s
    }

    var intValue: Int? {
        guard case let .number(n) = self else { return nil }
        let i = Int(n)
        guard Double(i) == n else { return nil }
        return i
    }

    var boolValue: Bool? {
        guard case let .bool(b) = self else { return nil }
        return b
    }

    var doubleValue: Double? {
        guard case let .number(n) = self else { return nil }
        return n
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(a) = self else { return nil }
        return a
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(o) = self else { return nil }
        return o
    }

    subscript(_ key: String) -> JSONValue? {
        guard case let .object(o) = self else { return nil }
        return o[key]
    }

    // MARK: Static helpers

    static func int(_ value: Int) -> JSONValue {
        .number(Double(value))
    }

    static func object(_ pairs: KeyValuePairs<String, JSONValue>) -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.value) }))
    }
}

// MARK: - Compact encoder

/// A shared compact encoder for JSON-RPC wire output (single-line, no pretty-print).
public enum JSONValueEncoder {
    public static let shared: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static func encode(_ value: JSONValue) throws -> Data {
        try self.shared.encode(value)
    }

    public static func encodeToString(_ value: JSONValue) throws -> String {
        let data = try encode(value)
        // JSON is always valid UTF-8; String(bytes:encoding:) returns nil only on corrupt data.
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Decoder helper

public enum JSONValueDecoder {
    public static let shared: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func decode(_ data: Data) throws -> JSONValue {
        try self.shared.decode(JSONValue.self, from: data)
    }

    public static func decode(_ string: String) throws -> JSONValue {
        try self.decode(Data(string.utf8))
    }
}
