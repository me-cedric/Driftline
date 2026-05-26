import Foundation

public struct HostTrustRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(host):\(port):\(algorithm)" }
    public var host: String
    public var port: Int
    public var algorithm: String
    public var fingerprint: String
    public var knownHostsLine: String?
    public var trustedAt: Date
    public var trustedByUser: Bool

    public init(
        host: String,
        port: Int,
        algorithm: String,
        fingerprint: String,
        knownHostsLine: String? = nil,
        trustedAt: Date = Date(),
        trustedByUser: Bool = true
    ) {
        self.host = host
        self.port = port
        self.algorithm = algorithm
        self.fingerprint = fingerprint
        self.knownHostsLine = knownHostsLine
        self.trustedAt = trustedAt
        self.trustedByUser = trustedByUser
    }
}

public enum HostVerificationResult: Equatable, Sendable {
    case trusted
    case unknown(fingerprint: String)
    case changed(previous: String, current: String)
}

public protocol HostTrustStore: Sendable {
    func verificationResult(host: String, port: Int, algorithm: String, fingerprint: String) async throws -> HostVerificationResult
    func trust(_ record: HostTrustRecord) async throws
}

public actor InMemoryHostTrustStore: HostTrustStore {
    private var records: [String: HostTrustRecord] = [:]

    public init(records: [HostTrustRecord] = []) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    public func verificationResult(host: String, port: Int, algorithm: String, fingerprint: String) async throws -> HostVerificationResult {
        let id = "\(host):\(port):\(algorithm)"
        guard let record = records[id] else { return .unknown(fingerprint: fingerprint) }
        return record.fingerprint == fingerprint ? .trusted : .changed(previous: record.fingerprint, current: fingerprint)
    }

    public func trust(_ record: HostTrustRecord) async throws {
        records[record.id] = record
    }
}

public actor JSONHostTrustStore: HostTrustStore {
    private let store: JSONFileStore<[HostTrustRecord]>

    public init(url: URL = DriftlineStoragePaths.hostTrustURL) {
        self.store = JSONFileStore(url: url)
    }

    public func verificationResult(host: String, port: Int, algorithm: String, fingerprint: String) async throws -> HostVerificationResult {
        let records = try await store.load(default: [])
        guard let record = records.first(where: { $0.host == host && $0.port == port && $0.algorithm == algorithm }) else {
            return .unknown(fingerprint: fingerprint)
        }
        if record.fingerprint == fingerprint {
            return .trusted
        }
        return .changed(previous: record.fingerprint, current: fingerprint)
    }

    public func trust(_ record: HostTrustRecord) async throws {
        var records = try await store.load(default: [])
        records.removeAll { $0.id == record.id }
        records.append(record)
        try await store.save(records)
    }
}

public struct HostFingerprint: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var algorithm: String
    public var fingerprint: String
    public var knownHostsLine: String

    public init(host: String, port: Int, algorithm: String, fingerprint: String, knownHostsLine: String = "") {
        self.host = host
        self.port = port
        self.algorithm = algorithm
        self.fingerprint = fingerprint
        self.knownHostsLine = knownHostsLine
    }
}

public protocol HostFingerprintProviding: Sendable {
    func fingerprint(host: String, port: Int) async throws -> HostFingerprint
}

public actor ManagedKnownHostsFile {
    private let url: URL

    public init(url: URL = DriftlineStoragePaths.knownHostsURL) {
        self.url = url
    }

    public func trust(_ record: HostTrustRecord) throws {
        guard let line = record.knownHostsLine?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let filtered = existing
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix(knownHostsPrefix(host: record.host, port: record.port)) && !$0.hasPrefix(record.host + " ") }
            .joined(separator: "\n")
        let next = ([filtered.trimmingCharacters(in: .whitespacesAndNewlines), line].filter { !$0.isEmpty }).joined(separator: "\n") + "\n"
        try next.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func knownHostsPrefix(host: String, port: Int) -> String {
        port == 22 ? "\(host) " : "[\(host)]:\(port) "
    }
}
