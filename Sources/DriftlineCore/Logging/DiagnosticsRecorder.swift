import Foundation

public enum DiagnosticLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct DiagnosticEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var level: DiagnosticLevel
    public var category: String
    public var message: String

    public init(timestamp: Date = Date(), level: DiagnosticLevel, category: String, message: String) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}

public actor DiagnosticsRecorder {
    public let fileURL: URL
    private let redactor: Redactor
    private let encoder: JSONEncoder

    public init(fileURL: URL = DiagnosticsRecorder.defaultFileURL(), redactor: Redactor = Redactor()) {
        self.fileURL = fileURL
        self.redactor = redactor
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func record(level: DiagnosticLevel, category: String, message: String) async {
        let event = DiagnosticEvent(
            level: level,
            category: self.redactor.redact(category),
            message: self.redactor.redact(message)
        )

        do {
            let directory = self.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try self.encoder.encode(event) + Data("\n".utf8)
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                let handle = try FileHandle(forWritingTo: self.fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: self.fileURL, options: .atomic)
            }
        } catch {
            // Diagnostics must never interrupt user workflows.
        }
    }

    public func clear() async throws {
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            try FileManager.default.removeItem(at: self.fileURL)
        }
    }

    public static func defaultFileURL(appName: String = "Driftline") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("diagnostics.jsonl")
    }
}
