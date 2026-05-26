import Foundation
import NIOSSH

public enum RemoteBackendKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case systemSSH
    case nativeSwiftExperimental

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .systemSSH:
            "System SSH"
        case .nativeSwiftExperimental:
            "Native Swift SSH"
        }
    }
}

public struct NativeSFTPBackendCapabilities: Equatable, Sendable {
    public var sshFoundation: String
    public var supportsPasswordCredentialRetrieval: Bool
    public var supportsStructuredCancellation: Bool
    public var supportsProductionSFTPSubsystem: Bool

    public init(
        sshFoundation: String = "SwiftNIO SSH",
        supportsPasswordCredentialRetrieval: Bool = true,
        supportsStructuredCancellation: Bool = true,
        supportsProductionSFTPSubsystem: Bool = true
    ) {
        self.sshFoundation = sshFoundation
        self.supportsPasswordCredentialRetrieval = supportsPasswordCredentialRetrieval
        self.supportsStructuredCancellation = supportsStructuredCancellation
        self.supportsProductionSFTPSubsystem = supportsProductionSFTPSubsystem
    }
}

public struct NativeSFTPClient: RemoteFileSystemClient {
    public let credentialStore: CredentialStore
    public let hostTrustStore: HostTrustStore
    public let capabilities: NativeSFTPBackendCapabilities
    private let connectionPool: NativeSFTPConnectionPool

    public init(
        credentialStore: CredentialStore,
        hostTrustStore: HostTrustStore,
        capabilities: NativeSFTPBackendCapabilities = NativeSFTPBackendCapabilities(),
        connectionPool: NativeSFTPConnectionPool = NativeSFTPConnectionPool()
    ) {
        self.credentialStore = credentialStore
        self.hostTrustStore = hostTrustStore
        self.capabilities = capabilities
        self.connectionPool = connectionPool
    }

    public func connect(to profile: ServerProfile) async throws -> ConnectionSession {
        guard profile.protocolKind == .sftp else {
            throw RemoteClientError.unsupportedProtocol(profile.protocolKind)
        }

        let connection = try await Self.makeConnection(profile: profile, credentialStore: credentialStore, hostTrustStore: hostTrustStore)
        let session = ConnectionSession(
            serverID: profile.id,
            state: .connected,
            protocolKind: .sftp,
            localPath: profile.localDefaultPath,
            remotePath: profile.remoteDefaultPath,
            connectedAt: Date()
        )
        await connectionPool.insert(connection, for: session.id)
        return session
    }

    public func disconnect(session: ConnectionSession) async throws {
        await connectionPool.remove(sessionID: session.id)
    }

    public func listDirectory(at path: String, profile: ServerProfile, session: ConnectionSession, preferences: FileListPreferences) async throws -> [FileItem] {
        try await connectionPool.connection(for: session.id).listDirectory(at: path, preferences: preferences)
    }

    public func createFolder(named name: String, in path: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try await connectionPool.connection(for: session.id).createFolder(named: name, in: path)
    }

    public func renameItem(at path: String, to newName: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try await connectionPool.connection(for: session.id).renameItem(at: path, to: newName)
    }

    public func deleteItem(at path: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try await connectionPool.connection(for: session.id).deleteItem(at: path)
    }

    public func itemExists(at path: String, profile: ServerProfile, session: ConnectionSession) async throws -> Bool {
        try await connectionPool.connection(for: session.id).itemExists(at: path)
    }

    public static func makeConnection(
        profile: ServerProfile,
        credentialStore: CredentialStore,
        hostTrustStore: HostTrustStore
    ) async throws -> NativeSFTPConnection {
        guard profile.protocolKind == .sftp else {
            throw RemoteClientError.unsupportedProtocol(profile.protocolKind)
        }

        switch profile.authenticationMethod {
        case .password(let reference):
            guard let password = try await credentialStore.readString(reference: reference) else {
                throw RemoteClientError.authenticationFailed
            }
            return try await NativeSFTPConnection.connect(
                profile: profile,
                authDelegate: NativeSFTPAuthFactory.passwordDelegate(username: profile.username, password: password),
                hostTrustStore: hostTrustStore
            )
        case .privateKey(let path, let passphrase):
            if let passphrase, try await credentialStore.readString(reference: passphrase) != nil {
                throw RemoteClientError.unsupportedAuthentication("Passphrase-protected private keys are not supported by the native backend yet. Use System SSH for this server.")
            }
            let contents = try String(contentsOfFile: NSString(string: path).expandingTildeInPath, encoding: .utf8)
            let key = try NativeSFTPPrivateKeyParser.parse(contents: contents)
            return try await NativeSFTPConnection.connect(
                profile: profile,
                authDelegate: NativeSFTPAuthFactory.offerSequence(username: profile.username, methods: [.privateKey(key)]),
                hostTrustStore: hostTrustStore
            )
        case .agent:
            throw RemoteClientError.nativeBackendUnavailable("SSH agent authentication is still planned for the native backend; use System SSH for agent-based servers.")
        case .none:
            throw RemoteClientError.unsupportedAuthentication("Native Swift SFTP requires password or private-key authentication.")
        }
    }
}
