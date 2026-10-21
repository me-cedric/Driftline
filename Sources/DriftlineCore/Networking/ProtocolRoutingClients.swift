import Foundation

/// Sends each call to the SFTP client or the FTP client, by the protocol of the profile or session.
public struct ProtocolRoutingRemoteFileSystemClient: RemoteFileSystemClient {
    private let sftp: RemoteFileSystemClient
    private let ftp: RemoteFileSystemClient

    public init(sftp: RemoteFileSystemClient, ftp: RemoteFileSystemClient) {
        self.sftp = sftp
        self.ftp = ftp
    }

    private func client(for kind: TransferProtocolKind) -> RemoteFileSystemClient {
        kind == .sftp ? self.sftp : self.ftp
    }

    public func connect(to profile: ServerProfile) async throws -> ConnectionSession {
        try await self.client(for: profile.protocolKind).connect(to: profile)
    }

    public func disconnect(session: ConnectionSession) async throws {
        try await self.client(for: session.protocolKind ?? .sftp).disconnect(session: session)
    }

    public func listDirectory(at path: String, profile: ServerProfile, session: ConnectionSession, preferences: FileListPreferences) async throws -> [FileItem] {
        try await self.client(for: profile.protocolKind).listDirectory(at: path, profile: profile, session: session, preferences: preferences)
    }

    public func createFolder(named name: String, in path: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try await self.client(for: profile.protocolKind).createFolder(named: name, in: path, profile: profile, session: session)
    }

    public func renameItem(at path: String, to newName: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try await self.client(for: profile.protocolKind).renameItem(at: path, to: newName, profile: profile, session: session)
    }

    public func deleteItem(at path: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try await self.client(for: profile.protocolKind).deleteItem(at: path, profile: profile, session: session)
    }

    public func itemExists(at path: String, profile: ServerProfile, session: ConnectionSession) async throws -> Bool {
        try await self.client(for: profile.protocolKind).itemExists(at: path, profile: profile, session: session)
    }
}

/// Sends each transfer to the SFTP or the FTP transfer client, and later calls for that job to the same client.
public actor ProtocolRoutingTransferClient: TransferClient {
    private let sftp: TransferClient
    private let ftp: TransferClient
    private var ftpJobs: Set<TransferJobID> = []

    public init(sftp: TransferClient, ftp: TransferClient) {
        self.sftp = sftp
        self.ftp = ftp
    }

    private func client(for id: TransferJobID) -> TransferClient {
        self.ftpJobs.contains(id) ? self.ftp : self.sftp
    }

    public func enqueue(_ job: TransferJob, profile: ServerProfile, onUpdate: (@Sendable (TransferJob) async -> Void)?) async throws {
        if profile.protocolKind != .sftp {
            self.ftpJobs.insert(job.id)
        }
        try await self.client(for: job.id).enqueue(job, profile: profile, onUpdate: onUpdate)
    }

    public func cancel(id: TransferJobID) async throws {
        // The rsync client stops all of its processes on cancel, so an FTP cancel must not reach it.
        try await self.client(for: id).cancel(id: id)
    }

    public func retry(id: TransferJobID) async throws {
        try await self.client(for: id).retry(id: id)
    }

    public func jobs() async -> [TransferJob] {
        await self.sftp.jobs() + self.ftp.jobs()
    }
}
