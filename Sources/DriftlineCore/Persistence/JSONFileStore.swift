import Foundation

public actor JSONFileStore<Value: Codable & Sendable> {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL) {
        self.url = url
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func load(default defaultValue: @autoclosure () -> Value) throws -> Value {
        guard FileManager.default.fileExists(atPath: self.url.path) else {
            return defaultValue()
        }
        let data = try Data(contentsOf: url)
        return try self.decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        let directory = self.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: self.url, options: [.atomic])
    }
}

public enum DriftlineStoragePaths {
    public static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Driftline", isDirectory: true)
    }

    public static var profilesURL: URL {
        applicationSupportDirectory.appendingPathComponent("server-profiles.json")
    }

    public static var hostTrustURL: URL {
        applicationSupportDirectory.appendingPathComponent("host-trust.json")
    }

    public static var knownHostsURL: URL {
        applicationSupportDirectory.appendingPathComponent("known_hosts")
    }

    public static var transferHistoryURL: URL {
        applicationSupportDirectory.appendingPathComponent("transfer-history.json")
    }

    public static var bookmarksURL: URL {
        applicationSupportDirectory.appendingPathComponent("bookmarks.json")
    }

    public static var recentsURL: URL {
        applicationSupportDirectory.appendingPathComponent("recent-servers.json")
    }

    public static var preferencesURL: URL {
        applicationSupportDirectory.appendingPathComponent("preferences.json")
    }
}
