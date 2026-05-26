import Foundation

public protocol LocalFileSystemClient: Sendable {
    func listDirectory(at path: String, preferences: FileListPreferences) async throws -> [FileItem]
    func createFolder(named name: String, in path: String) async throws
    func renameItem(at path: String, to newName: String) async throws
    func deleteItem(at path: String) async throws
    func itemExists(at path: String) async -> Bool
}

public protocol RemoteFileSystemClient: Sendable {
    func connect(to profile: ServerProfile) async throws -> ConnectionSession
    func disconnect(session: ConnectionSession) async throws
    func listDirectory(at path: String, profile: ServerProfile, session: ConnectionSession, preferences: FileListPreferences) async throws -> [FileItem]
    func createFolder(named name: String, in path: String, profile: ServerProfile, session: ConnectionSession) async throws
    func renameItem(at path: String, to newName: String, profile: ServerProfile, session: ConnectionSession) async throws
    func deleteItem(at path: String, profile: ServerProfile, session: ConnectionSession) async throws
    func itemExists(at path: String, profile: ServerProfile, session: ConnectionSession) async throws -> Bool
}

public protocol TransferClient: Sendable {
    func enqueue(_ job: TransferJob, profile: ServerProfile, onUpdate: (@Sendable (TransferJob) async -> Void)?) async throws
    func cancel(id: TransferJobID) async throws
    func retry(id: TransferJobID) async throws
    func jobs() async -> [TransferJob]
}

public extension TransferClient {
    func enqueue(_ job: TransferJob, profile: ServerProfile) async throws {
        try await enqueue(job, profile: profile, onUpdate: nil)
    }
}

public struct UnsupportedRemoteFileSystemClient: RemoteFileSystemClient {
    public var protocolKind: TransferProtocolKind

    public init(protocolKind: TransferProtocolKind) {
        self.protocolKind = protocolKind
    }

    public func connect(to profile: ServerProfile) async throws -> ConnectionSession {
        throw RemoteClientError.unsupportedProtocol(profile.protocolKind)
    }

    public func disconnect(session: ConnectionSession) async throws {}

    public func listDirectory(at path: String, profile: ServerProfile, session: ConnectionSession, preferences: FileListPreferences) async throws -> [FileItem] {
        throw RemoteClientError.unsupportedProtocol(protocolKind)
    }

    public func createFolder(named name: String, in path: String, profile: ServerProfile, session: ConnectionSession) async throws {
        throw RemoteClientError.unsupportedProtocol(protocolKind)
    }

    public func renameItem(at path: String, to newName: String, profile: ServerProfile, session: ConnectionSession) async throws {
        throw RemoteClientError.unsupportedProtocol(protocolKind)
    }

    public func deleteItem(at path: String, profile: ServerProfile, session: ConnectionSession) async throws {
        throw RemoteClientError.unsupportedProtocol(protocolKind)
    }

    public func itemExists(at path: String, profile: ServerProfile, session: ConnectionSession) async throws -> Bool {
        throw RemoteClientError.unsupportedProtocol(protocolKind)
    }
}

public enum RemoteClientError: Error, Equatable, LocalizedError {
    case unsupportedProtocol(TransferProtocolKind)
    case connectionFailed(String)
    case authenticationFailed
    case hostFingerprintChanged
    case hostNotTrusted(host: String, port: Int, algorithm: String, fingerprint: String, knownHostsLine: String)
    case commandFailed(String)
    case unsupportedAuthentication(String)
    case itemAlreadyExists(String)
    case nativeBackendUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedProtocol(let kind):
            "\(kind.rawValue.uppercased()) is scaffolded but not enabled in this build."
        case .connectionFailed:
            "The connection could not be established."
        case .authenticationFailed:
            "Authentication failed. Check the username, key, or password."
        case .hostFingerprintChanged:
            "The host fingerprint changed. Review the host before continuing."
        case .hostNotTrusted(_, _, let algorithm, let fingerprint, _):
            "Trust this \(algorithm) host fingerprint before connecting: \(fingerprint)"
        case .commandFailed(let message):
            message
        case .unsupportedAuthentication(let message):
            message
        case .itemAlreadyExists(let path):
            "An item already exists at \(path)."
        case .nativeBackendUnavailable(let message):
            message
        }
    }
}
