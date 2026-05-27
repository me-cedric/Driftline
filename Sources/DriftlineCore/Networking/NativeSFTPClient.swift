import Foundation
import NIOSSH

public enum RemoteBackendKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case systemSSH
    case nativeSwiftExperimental

    public var id: String {
        rawValue
    }

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

        let connection = try await Self.makeConnection(profile: profile, credentialStore: self.credentialStore, hostTrustStore: self.hostTrustStore)
        let session = ConnectionSession(
            serverID: profile.id,
            state: .connected,
            protocolKind: .sftp,
            localPath: profile.localDefaultPath,
            remotePath: profile.remoteDefaultPath,
            connectedAt: Date()
        )
        await self.connectionPool.insert(connection, for: session.id)
        return session
    }

    public func disconnect(session: ConnectionSession) async throws {
        await self.connectionPool.remove(sessionID: session.id)
    }

    public func listDirectory(at path: String, profile _: ServerProfile, session: ConnectionSession, preferences: FileListPreferences) async throws -> [FileItem] {
        try await self.connectionPool.connection(for: session.id).listDirectory(at: path, preferences: preferences)
    }

    public func createFolder(named name: String, in path: String, profile _: ServerProfile, session: ConnectionSession) async throws {
        try await self.connectionPool.connection(for: session.id).createFolder(named: name, in: path)
    }

    public func renameItem(at path: String, to newName: String, profile _: ServerProfile, session: ConnectionSession) async throws {
        try await self.connectionPool.connection(for: session.id).renameItem(at: path, to: newName)
    }

    public func deleteItem(at path: String, profile _: ServerProfile, session: ConnectionSession) async throws {
        try await self.connectionPool.connection(for: session.id).deleteItem(at: path)
    }

    public func itemExists(at path: String, profile _: ServerProfile, session: ConnectionSession) async throws -> Bool {
        try await self.connectionPool.connection(for: session.id).itemExists(at: path)
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
        case let .password(reference):
            guard let password = try await credentialStore.readString(reference: reference) else {
                throw RemoteClientError.authenticationFailed
            }
            return try await self.connectWithRetry(
                profile: profile,
                authDelegate: { NativeSFTPAuthFactory.passwordDelegate(username: profile.username, password: password) },
                hostTrustStore: hostTrustStore
            )
        case let .privateKey(path, passphraseRef):
            let resolvedPassphrase: String?
            if let passphraseRef {
                resolvedPassphrase = try await credentialStore.readString(reference: passphraseRef)
            } else {
                resolvedPassphrase = nil
            }
            let contents = try String(contentsOfFile: NSString(string: path).expandingTildeInPath, encoding: .utf8)
            let key = try NativeSFTPPrivateKeyParser.parse(contents: contents, passphrase: resolvedPassphrase)
            return try await self.connectWithRetry(
                profile: profile,
                authDelegate: { NativeSFTPAuthFactory.offerSequence(username: profile.username, methods: [.privateKey(key)]) },
                hostTrustStore: hostTrustStore
            )
        case .agent:
            let agentClient = SSHAgentClient()
            guard let agent = agentClient else {
                throw RemoteClientError.nativeBackendUnavailable("SSH_AUTH_SOCK is not set. Start ssh-agent and add your keys with ssh-add.")
            }
            let identities = try await agent.listIdentities()
            guard !identities.isEmpty else {
                throw RemoteClientError.nativeBackendUnavailable("The SSH agent has no loaded identities. Run ssh-add to load your keys.")
            }
            throw RemoteClientError.nativeBackendUnavailable("SSH agent signing is not directly supported by the SwiftNIO SSH 0.11.0 API. Use System SSH backend for agent-based connections.")
        case .none:
            throw RemoteClientError.unsupportedAuthentication("Native Swift SFTP requires password or private-key authentication.")
        }
    }

    private static func connectWithRetry(
        profile: ServerProfile,
        authDelegate: () -> NIOSSHClientUserAuthenticationDelegate,
        hostTrustStore: HostTrustStore
    ) async throws -> NativeSFTPConnection {
        do {
            return try await NativeSFTPConnection.connect(
                profile: profile,
                authDelegate: authDelegate(),
                hostTrustStore: hostTrustStore
            )
        } catch {
            guard self.isTransientHandshakeClose(error) else { throw error }
            try await Task.sleep(nanoseconds: 250_000_000)
            return try await NativeSFTPConnection.connect(
                profile: profile,
                authDelegate: authDelegate(),
                hostTrustStore: hostTrustStore
            )
        }
    }

    private static func isTransientHandshakeClose(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("end of file")
            || description.contains("connection reset")
            || description.contains("connection closed")
    }
}
