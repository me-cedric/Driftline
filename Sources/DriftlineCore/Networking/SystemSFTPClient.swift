import Foundation

/// Runs each operation as `sftp -b -` with the system OpenSSH client. OpenSSH negotiates every common algorithm
/// (RSA host keys, DH key exchange, chacha20, CBC) and handles password and keyboard-interactive login through SSH_ASKPASS.
public struct SystemSFTPClient: RemoteFileSystemClient {
    private let processExecutor: SystemProcessExecuting
    private let hostTrustStore: HostTrustStore?
    private let hostFingerprintProvider: HostFingerprintProviding?
    private let credentialStore: CredentialStore?
    private let knownHostsURL: URL?

    public init(
        processExecutor: SystemProcessExecuting = FoundationProcessExecutor(),
        hostTrustStore: HostTrustStore? = nil,
        hostFingerprintProvider: HostFingerprintProviding? = nil,
        credentialStore: CredentialStore? = nil,
        knownHostsURL: URL? = DriftlineStoragePaths.knownHostsURL
    ) {
        self.processExecutor = processExecutor
        self.hostTrustStore = hostTrustStore
        self.hostFingerprintProvider = hostFingerprintProvider
        self.credentialStore = credentialStore
        self.knownHostsURL = knownHostsURL
    }

    public static func secureDefault(credentialStore: CredentialStore? = nil) -> SystemSFTPClient {
        let executor = FoundationProcessExecutor()
        return SystemSFTPClient(
            processExecutor: executor,
            hostTrustStore: JSONHostTrustStore(),
            hostFingerprintProvider: SystemHostFingerprintProvider(processExecutor: executor),
            credentialStore: credentialStore
        )
    }

    public func connect(to profile: ServerProfile) async throws -> ConnectionSession {
        guard profile.protocolKind == .sftp else {
            throw RemoteClientError.unsupportedProtocol(profile.protocolKind)
        }
        do {
            // Log in once here, so a wrong password or a refused login shows at connect time.
            // ssh checks the host key against the managed known_hosts file (StrictHostKeyChecking=yes).
            try await self.runBatch("pwd\n", profile: profile, timeout: 30)
        } catch RemoteClientError.hostFingerprintChanged {
            // Scan only on first contact or on a mismatch: every scan opens unauthenticated connections,
            // and OpenSSH 9.8+ servers penalize a source address that opens many of them (PerSourcePenalties).
            throw try await self.hostKeyError(for: profile)
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

    private func hostKeyError(for profile: ServerProfile) async throws -> RemoteClientError {
        guard let hostTrustStore, let hostFingerprintProvider else { return .hostFingerprintChanged }
        let fingerprint = try await hostFingerprintProvider.fingerprint(host: profile.host, port: profile.port)
        let result = try await hostTrustStore.verificationResult(
            host: profile.host,
            port: profile.port,
            algorithm: fingerprint.algorithm,
            fingerprint: fingerprint.fingerprint
        )
        switch result {
        case .trusted, .unknown:
            // .trusted here means the record exists but known_hosts lost the line: trusting again writes it back.
            return .hostNotTrusted(host: profile.host, port: profile.port, algorithm: fingerprint.algorithm, fingerprint: fingerprint.fingerprint, knownHostsLine: fingerprint.knownHostsLine)
        case .changed:
            return .hostFingerprintChanged
        }
    }

    public func listDirectory(at path: String, profile: ServerProfile, session: ConnectionSession, preferences: FileListPreferences) async throws -> [FileItem] {
        try self.requireConnected(session)
        let result = try await self.runBatch(SFTPBatchCommandBuilder.listCommands(path: path), profile: profile, timeout: 60)
        let directory = SFTPLongListingParser.workingDirectory(in: result.standardOutput) ?? path
        return SFTPLongListingParser.parse(result.standardOutput, directory: directory, preferences: preferences)
    }

    public func createFolder(named name: String, in path: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try self.requireConnected(session)
        try await self.runBatch(SFTPBatchCommandBuilder.createFolderCommand(name: name, in: path), profile: profile, timeout: 30)
    }

    public func renameItem(at path: String, to newName: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try self.requireConnected(session)
        try await self.runBatch(SFTPBatchCommandBuilder.renameCommand(path: path, newName: newName), profile: profile, timeout: 30)
    }

    public func deleteItem(at path: String, profile: ServerProfile, session: ConnectionSession) async throws {
        try self.requireConnected(session)
        guard !["", "/", "~", "~/", "."].contains(path) else {
            throw RemoteClientError.commandFailed("Driftline does not delete the root or home folder.")
        }
        // `cd` follows a link to a folder, so look at the entry itself first: a link is removed, never its target.
        let name = (path as NSString).lastPathComponent
        let parent = try await self.runBatch(SFTPBatchCommandBuilder.listCommands(path: SFTPBatchCommandBuilder.parentPath(of: path)), profile: profile, timeout: 60)
        let entry = SFTPLongListingParser.parse(parent.standardOutput, directory: "", preferences: FileListPreferences(showHiddenFiles: true)).first { $0.name == name }
        if entry?.kind == .folder {
            try await self.deleteRecursively(path, profile: profile)
        } else {
            try await self.runBatch(SFTPBatchCommandBuilder.removeFileCommand(path: path), profile: profile, timeout: 30)
        }
    }

    public func itemExists(at path: String, profile: ServerProfile, session: ConnectionSession) async throws -> Bool {
        try self.requireConnected(session)
        let result = try await self.run(SFTPBatchCommandBuilder.existsCommand(path: path), profile: profile, timeout: 15)
        // sftp exits with 1 when a batch command fails; 255 means ssh itself failed.
        if result.exitCode == 1 {
            return false
        }
        try self.check(result)
        return true
    }

    /// Deletes a folder that is known to be a real folder. Children typed `l` are links and are removed as files.
    private func deleteRecursively(_ path: String, profile: ServerProfile) async throws {
        let listing = try await self.runBatch(SFTPBatchCommandBuilder.listCommands(path: path), profile: profile, timeout: 60)
        let directory = SFTPLongListingParser.workingDirectory(in: listing.standardOutput) ?? path
        let children = SFTPLongListingParser.parse(listing.standardOutput, directory: directory, preferences: FileListPreferences(showHiddenFiles: true))
        for child in children where child.kind == .folder {
            try await self.deleteRecursively(child.path, profile: profile)
        }
        var commands = try children.filter { $0.kind != .folder }.map { try SFTPBatchCommandBuilder.removeFileCommand(path: $0.path) }.joined()
        commands += try SFTPBatchCommandBuilder.removeFolderCommand(path: path)
        try await self.runBatch(commands, profile: profile, timeout: 60)
    }

    @discardableResult
    private func runBatch(_ commands: String, profile: ServerProfile, timeout: TimeInterval) async throws -> ProcessResult {
        let result = try await self.run(commands, profile: profile, timeout: timeout)
        try self.check(result)
        return result
    }

    private func run(_ commands: String, profile: ServerProfile, timeout: TimeInterval) async throws -> ProcessResult {
        let arguments = try SSHCommandBuilder.sftpBatchArguments(for: profile, knownHostsURL: self.knownHostsURL)
        let askPass = try await SSHAskPassSession.make(for: profile, credentialStore: self.credentialStore)
        defer { askPass?.close() }
        return try await self.processExecutor.run(
            executable: "/usr/bin/sftp",
            arguments: arguments,
            environment: askPass?.environment ?? [:],
            standardInput: Data(commands.utf8),
            timeout: timeout
        )
    }

    private func check(_ result: ProcessResult) throws {
        guard result.exitCode != 0 else { return }
        throw SSHErrorMapper.error(exitCode: result.exitCode, standardError: result.standardError)
    }

    private func requireConnected(_ session: ConnectionSession) throws {
        guard session.state == .connected else {
            throw RemoteClientError.connectionFailed("Connect before you use remote files.")
        }
    }
}

/// Turns OpenSSH and sftp failures into errors that tell the user what to change.
public enum SSHErrorMapper {
    public static func error(exitCode: Int32, standardError: String) -> RemoteClientError {
        let message = Redactor().redact(standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        let lowered = message.lowercased()
        if exitCode == 124 {
            return .connectionFailed("The server did not answer in time.")
        }
        if lowered.contains("permission denied (") || lowered.contains("too many authentication failures") {
            return .authenticationFailed
        }
        if lowered.contains("host key verification failed") || lowered.contains("remote host identification has changed") {
            return .hostFingerprintChanged
        }
        if lowered.contains("no matching") || lowered.contains("unable to negotiate") {
            return .connectionFailed("The server and this Mac have no common SSH algorithm. \(message)")
        }
        let networkFailures = ["could not resolve hostname", "connection refused", "operation timed out", "connection timed out", "no route to host", "connection closed"]
        if networkFailures.contains(where: lowered.contains) {
            return .connectionFailed(message)
        }
        return .commandFailed(message.isEmpty ? "The remote operation failed." : message)
    }
}
