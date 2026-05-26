import Foundation

public struct CLIRequest: Codable, Equatable, Sendable {
    public var localPath: String
    public var openInNewTab: Bool
    public var requestedAt: Date

    public init(localPath: String, openInNewTab: Bool = false, requestedAt: Date = Date()) {
        self.localPath = localPath
        self.openInNewTab = openInNewTab
        self.requestedAt = requestedAt
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
