import Foundation

/// Servers on which the Native Swift SSH backend cannot run, learned during the app session.
public actor NativeSSHSupportRegistry {
    private var unsupported: Set<String> = []

    public init() {}

    /// SwiftNIO SSH has no SSH agent signing; any other gap shows when a connection fails.
    public func needsSystemSSH(_ profile: ServerProfile) -> Bool {
        if case .agent = profile.authenticationMethod {
            return true
        }
        return self.unsupported.contains(Self.key(profile))
    }

    public func markUnsupported(_ profile: ServerProfile) {
        self.unsupported.insert(Self.key(profile))
    }

    private static func key(_ profile: ServerProfile) -> String {
        "\(profile.host):\(profile.port)"
    }
}

/// Tries the Native Swift SSH client and uses System SSH for a server it cannot handle (RSA-only host key,
/// Diffie-Hellman key exchange, SSH agent login). A wrong password or a host key problem never falls back:
/// that would hide a security warning or try the password twice.
public actor BackendFallbackRemoteFileSystemClient: RemoteFileSystemClient {
    private let native: RemoteFileSystemClient
    private let system: RemoteFileSystemClient
    private let registry: NativeSSHSupportRegistry
    private var systemSessions: Set<UUID> = []

    public init(native: RemoteFileSystemClient, system: RemoteFileSystemClient, registry: NativeSSHSupportRegistry) {
        self.native = native
        self.system = system
        self.registry = registry
    }

    public func connect(to profile: ServerProfile) async throws -> ConnectionSession {
        if await !self.registry.needsSystemSSH(profile) {
            do {
                return try await self.native.connect(to: profile)
            } catch RemoteClientError.nativeBackendUnavailable {
                await self.registry.markUnsupported(profile)
            }
        }
        var session = try await self.system.connect(to: profile)
        session.fallbackBackend = .systemSSH
        self.systemSessions.insert(session.id)
        return session
    }

    private func client(for session: ConnectionSession) -> RemoteFileSystemClient {
        self.systemSessions.contains(session.id) ? self.system : self.native
    }

    public func disconnect(session: ConnectionSession) async throws {
        try await self.client(for: session).disconnect(session: session)
        self.systemSessions.remove(session.id)
    }

    public func listDirectory(at path: String, profile: ServerProfile, session: ConnectionSession, preferences: FileListPreferences) async throws -> [FileItem] {
        try await self.client(for: session).listDirectory(at: path, profile: profile, session: session, preferences: preferences)
    }

    public func createFolder(named name: String, in path: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try await self.client(for: session).createFolder(named: name, in: path, profile: profile, session: session)
    }

    public func renameItem(at path: String, to newName: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try await self.client(for: session).renameItem(at: path, to: newName, profile: profile, session: session)
    }

    public func deleteItem(at path: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try await self.client(for: session).deleteItem(at: path, profile: profile, session: session)
    }

    public func itemExists(at path: String, profile: ServerProfile, session: ConnectionSession) async throws -> Bool {
        try await self.client(for: session).itemExists(at: path, profile: profile, session: session)
    }
}

/// Sends a transfer to System SSH when the registry knows that Native Swift SSH cannot reach the server.
public actor BackendFallbackTransferClient: TransferClient {
    private let native: TransferClient
    private let system: TransferClient
    private let registry: NativeSSHSupportRegistry
    private var systemJobs: Set<TransferJobID> = []

    public init(native: TransferClient, system: TransferClient, registry: NativeSSHSupportRegistry) {
        self.native = native
        self.system = system
        self.registry = registry
    }

    private func client(for id: TransferJobID) -> TransferClient {
        self.systemJobs.contains(id) ? self.system : self.native
    }

    public func enqueue(_ job: TransferJob, profile: ServerProfile, onUpdate: (@Sendable (TransferJob) async -> Void)?) async throws {
        if await self.registry.needsSystemSSH(profile) {
            self.systemJobs.insert(job.id)
        }
        try await self.client(for: job.id).enqueue(job, profile: profile, onUpdate: onUpdate)
    }

    public func cancel(id: TransferJobID) async throws {
        try await self.client(for: id).cancel(id: id)
    }

    public func retry(id: TransferJobID) async throws {
        try await self.client(for: id).retry(id: id)
    }

    public func jobs() async -> [TransferJob] {
        await self.native.jobs() + self.system.jobs()
    }
}
