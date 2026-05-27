import Foundation

public struct SystemSFTPClient: RemoteFileSystemClient {
    private let processExecutor: SystemProcessExecuting
    private let hostTrustStore: HostTrustStore?
    private let hostFingerprintProvider: HostFingerprintProviding?

    public init(
        processExecutor: SystemProcessExecuting = FoundationProcessExecutor(),
        hostTrustStore: HostTrustStore? = nil,
        hostFingerprintProvider: HostFingerprintProviding? = nil
    ) {
        self.processExecutor = processExecutor
        self.hostTrustStore = hostTrustStore
        self.hostFingerprintProvider = hostFingerprintProvider
    }

    public static func secureDefault() -> SystemSFTPClient {
        let executor = FoundationProcessExecutor()
        return SystemSFTPClient(
            processExecutor: executor,
            hostTrustStore: JSONHostTrustStore(),
            hostFingerprintProvider: SystemHostFingerprintProvider(processExecutor: executor)
        )
    }

    public func connect(to profile: ServerProfile) async throws -> ConnectionSession {
        guard profile.protocolKind == .sftp else {
            throw RemoteClientError.unsupportedProtocol(profile.protocolKind)
        }
        if let hostTrustStore, let hostFingerprintProvider {
            let fingerprint = try await hostFingerprintProvider.fingerprint(host: profile.host, port: profile.port)
            let result = try await hostTrustStore.verificationResult(
                host: profile.host,
                port: profile.port,
                algorithm: fingerprint.algorithm,
                fingerprint: fingerprint.fingerprint
            )
            switch result {
            case .trusted:
                break
            case .unknown:
                throw RemoteClientError.hostNotTrusted(host: profile.host, port: profile.port, algorithm: fingerprint.algorithm, fingerprint: fingerprint.fingerprint, knownHostsLine: fingerprint.knownHostsLine)
            case .changed:
                throw RemoteClientError.hostFingerprintChanged
            }
        }
        return ConnectionSession(
            serverID: profile.id,
            state: .connected,
            protocolKind: .sftp,
            localPath: profile.localDefaultPath,
            remotePath: profile.remoteDefaultPath,
            connectedAt: Date()
        )
    }

    public func disconnect(session _: ConnectionSession) async throws {}

    public func listDirectory(at path: String, profile: ServerProfile, session: ConnectionSession, preferences: FileListPreferences) async throws -> [FileItem] {
        guard session.state == .connected else {
            throw RemoteClientError.connectionFailed("Connect before listing remote files.")
        }
        let arguments = try SSHCommandBuilder.remoteListArguments(for: profile, path: path)
        let result = try await processExecutor.run(executable: "/usr/bin/ssh", arguments: arguments, timeout: 30)
        guard result.exitCode == 0 else {
            let redacted = Redactor().redact(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
            throw RemoteClientError.commandFailed(redacted.isEmpty ? "Remote listing failed." : redacted)
        }
        return RemoteFindParser.parse(result.standardOutput, preferences: preferences)
    }

    public func createFolder(named name: String, in path: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try await self.runRemoteCommand(RemoteFileCommandBuilder.createFolderCommand(name: name, in: path), profile: profile, session: session)
    }

    public func renameItem(at path: String, to newName: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try await self.runRemoteCommand(RemoteFileCommandBuilder.renameCommand(path: path, newName: newName), profile: profile, session: session)
    }

    public func deleteItem(at path: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try await self.runRemoteCommand(RemoteFileCommandBuilder.deleteCommand(path: path), profile: profile, session: session)
    }

    public func itemExists(at path: String, profile: ServerProfile, session: ConnectionSession) async throws -> Bool {
        guard session.state == .connected else {
            throw RemoteClientError.connectionFailed("Connect before checking remote files.")
        }
        var arguments = try SSHCommandBuilder.baseArguments(for: profile)
        arguments.append("\(profile.username)@\(profile.host)")
        arguments.append(RemoteFileCommandBuilder.existsCommand(path: path))
        let result = try await processExecutor.run(executable: "/usr/bin/ssh", arguments: arguments, timeout: 15)
        return result.exitCode == 0
    }

    private func runRemoteCommand(_ command: String, profile: ServerProfile, session: ConnectionSession) async throws {
        guard session.state == .connected else {
            throw RemoteClientError.connectionFailed("Connect before modifying remote files.")
        }
        var arguments = try SSHCommandBuilder.baseArguments(for: profile)
        arguments.append("\(profile.username)@\(profile.host)")
        arguments.append(command)
        let result = try await processExecutor.run(executable: "/usr/bin/ssh", arguments: arguments, timeout: 30)
        guard result.exitCode == 0 else {
            let redacted = Redactor().redact(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
            throw RemoteClientError.commandFailed(redacted.isEmpty ? "Remote operation failed." : redacted)
        }
    }
}
