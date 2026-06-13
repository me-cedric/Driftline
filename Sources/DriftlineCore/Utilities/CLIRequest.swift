import Foundation

public enum CLIRequestIntent: Equatable, Sendable {
    case openPath(String)
    case openBookmark(String)
}

extension CLIRequestIntent: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case openPath
        case openBookmark
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)
        switch kind {
        case .openPath:
            self = .openPath(value)
        case .openBookmark:
            self = .openBookmark(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .openPath(path):
            try container.encode(Kind.openPath, forKey: .kind)
            try container.encode(path, forKey: .value)
        case let .openBookmark(name):
            try container.encode(Kind.openBookmark, forKey: .kind)
            try container.encode(name, forKey: .value)
        }
    }
}

public struct CLIRequest: Codable, Equatable, Sendable {
    public var intent: CLIRequestIntent
    public var openInNewTab: Bool
    public var requestedAt: Date

    public var localPath: String? {
        if case let .openPath(path) = intent {
            return path
        }
        return nil
    }

    public var bookmarkName: String? {
        if case let .openBookmark(name) = intent {
            return name
        }
        return nil
    }

    public init(intent: CLIRequestIntent, openInNewTab: Bool = false, requestedAt: Date = Date()) {
        self.intent = intent
        self.openInNewTab = openInNewTab
        self.requestedAt = requestedAt
    }

    public init(localPath: String, openInNewTab: Bool = false, requestedAt: Date = Date()) {
        self.intent = .openPath(localPath)
        self.openInNewTab = openInNewTab
        self.requestedAt = requestedAt
    }

    private enum CodingKeys: String, CodingKey {
        case intent
        case localPath
        case openInNewTab
        case requestedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intent = try container.decodeIfPresent(CLIRequestIntent.self, forKey: .intent) {
            self.intent = intent
        } else {
            self.intent = try .openPath(container.decode(String.self, forKey: .localPath))
        }
        self.openInNewTab = try container.decodeIfPresent(Bool.self, forKey: .openInNewTab) ?? false
        self.requestedAt = try container.decodeIfPresent(Date.self, forKey: .requestedAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.intent, forKey: .intent)
        if let localPath {
            try container.encode(localPath, forKey: .localPath)
        }
        try container.encode(self.openInNewTab, forKey: .openInNewTab)
        try container.encode(self.requestedAt, forKey: .requestedAt)
    }
}

public enum CLIRequestStore {
    public static var requestURL: URL {
        DriftlineStoragePaths.applicationSupportDirectory.appendingPathComponent("cli-request.json")
    }

    public static func save(_ request: CLIRequest, url: URL = requestURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        try data.write(to: url, options: [.atomic])
    }

    public static func consume(url: URL = requestURL) throws -> CLIRequest? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CLIRequest.self, from: data)
    }
}
