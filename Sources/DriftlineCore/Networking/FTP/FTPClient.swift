import Foundation

/// FTPS certificates that the user trusted, kept for the app session so each operation does not ask the trust store again.
public actor FTPTLSPinCache {
    private var pins: [String: String] = [:]

    public init() {}

    func pin(host: String, port: Int) -> String? {
        self.pins["\(host):\(port)"]
    }

    func set(_ pin: String, host: String, port: Int) {
        self.pins["\(host):\(port)"] = pin
    }
}

/// Opens logged-in FTP connections on a background thread and applies the user's certificate trust decisions.
struct FTPSessionRunner {
    static let trustAlgorithm = "TLS"

    let credentialStore: CredentialStore?
    let hostTrustStore: HostTrustStore?
    let pinCache: FTPTLSPinCache

    func password(for profile: ServerProfile) async throws -> String? {
        switch profile.authenticationMethod {
        case let .password(reference):
            guard let password = try await self.credentialStore?.readString(reference: reference) else {
                throw RemoteClientError.unsupportedAuthentication("No password is saved for this server. Edit the server and enter the password.")
            }
            return password
        case .none:
            return nil
        case .privateKey, .agent:
            throw RemoteClientError.unsupportedAuthentication("FTP and FTPS log in with a user name and password. Choose password or no authentication.")
        }
    }

    /// Runs `body` on a new connection and closes it. An untrusted certificate becomes a trust prompt, or a retry when the user trusted it before.
    @discardableResult
    func withConnection<T: Sendable>(_ profile: ServerProfile, _ body: @escaping @Sendable (FTPConnection) throws -> T) async throws -> T {
        let password = try await self.password(for: profile)
        let pin = await self.pinCache.pin(host: profile.host, port: profile.port)
        do {
            return try await Self.run(profile, password: password, pin: pin, body)
        } catch let untrusted as FTPUntrustedCertificate {
            guard let hostTrustStore else { throw RemoteClientError.connectionFailed("macOS does not trust the server certificate.") }
            switch try await hostTrustStore.verificationResult(host: profile.host, port: profile.port, algorithm: Self.trustAlgorithm, fingerprint: untrusted.fingerprint) {
            case .trusted:
                await self.pinCache.set(untrusted.fingerprint, host: profile.host, port: profile.port)
                return try await Self.run(profile, password: password, pin: untrusted.fingerprint, body)
            case .unknown:
                throw RemoteClientError.hostNotTrusted(host: profile.host, port: profile.port, algorithm: Self.trustAlgorithm, fingerprint: untrusted.fingerprint, knownHostsLine: "")
            case .changed:
                throw RemoteClientError.hostFingerprintChanged
            }
        }
    }

    private static func run<T: Sendable>(_ profile: ServerProfile, password: String?, pin: String?, _ body: @escaping @Sendable (FTPConnection) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let connection = try FTPConnection(profile: profile, password: password, trustedFingerprint: pin)
                    defer { connection.quit() }
                    try continuation.resume(returning: body(connection))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func list(_ path: String, profile: ServerProfile, showHidden: Bool) async throws -> [FileItem] {
        let output = try await self.withConnection(profile) { try $0.list(path, showHidden: showHidden) }
        return FTPListParser.parse(output, directory: path, preferences: FileListPreferences(showHiddenFiles: showHidden))
    }
}

/// FTP and FTPS in Swift: passive mode (EPSV, then PASV with the control host), explicit and implicit TLS,
/// and TLS session reuse on data connections, which most FTPS servers require.
public struct FTPClient: RemoteFileSystemClient {
    private let runner: FTPSessionRunner

    public init(credentialStore: CredentialStore? = nil, hostTrustStore: HostTrustStore? = nil, pinCache: FTPTLSPinCache = FTPTLSPinCache()) {
        self.runner = FTPSessionRunner(credentialStore: credentialStore, hostTrustStore: hostTrustStore, pinCache: pinCache)
    }

    public func connect(to profile: ServerProfile) async throws -> ConnectionSession {
        guard profile.protocolKind == .ftp || profile.protocolKind == .ftps else {
            throw RemoteClientError.unsupportedProtocol(profile.protocolKind)
        }
        _ = try await self.runner.withConnection(profile) { _ in true }
        return ConnectionSession(
            serverID: profile.id,
            state: .connected,
            protocolKind: profile.protocolKind,
            localPath: profile.localDefaultPath,
            remotePath: profile.remoteDefaultPath,
            connectedAt: Date()
        )
    }

    public func disconnect(session _: ConnectionSession) async throws {}

    public func listDirectory(at path: String, profile: ServerProfile, session _: ConnectionSession, preferences: FileListPreferences) async throws -> [FileItem] {
        let items = try await self.runner.list(path, profile: profile, showHidden: preferences.showHiddenFiles)
        return FileItemSorter.sort(items, preferences: preferences)
    }

    public func createFolder(named name: String, in path: String, profile: ServerProfile, session _: ConnectionSession) async throws {
        let target = try FTPCommandBuilder.commandPath(SFTPBatchCommandBuilder.join(path, name))
        try await self.runner.withConnection(profile) { try $0.expect($0.send("MKD \(target)"), 257, 250) }
    }

    public func renameItem(at path: String, to newName: String, profile: ServerProfile, session _: ConnectionSession) async throws {
        let source = try FTPCommandBuilder.commandPath(path)
        let destination = try FTPCommandBuilder.commandPath(SFTPBatchCommandBuilder.join(SFTPBatchCommandBuilder.parentPath(of: path), newName))
        try await self.runner.withConnection(profile) { connection in
            try connection.expect(connection.send("RNFR \(source)"), 350)
            try connection.expect(connection.send("RNTO \(destination)"), 250)
        }
    }

    public func deleteItem(at path: String, profile: ServerProfile, session _: ConnectionSession) async throws {
        guard !["", "/", "~", "~/", "."].contains(path) else {
            throw RemoteClientError.commandFailed("Driftline does not delete the root or home folder.")
        }
        let target = try FTPCommandBuilder.commandPath(path)
        let deleted = try await self.runner.withConnection(profile) { try $0.send("DELE \(target)").code == 250 }
        // DELE fails on a folder: delete its contents, then the folder.
        if !deleted {
            try await self.deleteFolder(path, profile: profile)
        }
    }

    public func itemExists(at path: String, profile: ServerProfile, session _: ConnectionSession) async throws -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let parent = SFTPBatchCommandBuilder.parentPath(of: path)
        do {
            return try await self.runner.list(parent, profile: profile, showHidden: true).contains { $0.name == name }
        } catch RemoteClientError.commandFailed {
            return false
        }
    }

    private func deleteFolder(_ path: String, profile: ServerProfile) async throws {
        let children = try await self.runner.list(path, profile: profile, showHidden: true)
        for child in children where child.kind == .folder {
            try await self.deleteFolder(child.path, profile: profile)
        }
        let files = try children.filter { $0.kind != .folder }.map { try FTPCommandBuilder.commandPath($0.path) }
        let folder = try FTPCommandBuilder.commandPath(path)
        try await self.runner.withConnection(profile) { connection in
            for file in files {
                try connection.expect(connection.send("DELE \(file)"), 250)
            }
            try connection.expect(connection.send("RMD \(folder)"), 250)
        }
    }
}

/// Stops a running FTP transfer from another thread.
final class FTPCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        self.lock.lock()
        defer { lock.unlock() }
        return self.cancelled
    }

    func cancel() {
        self.lock.lock()
        self.cancelled = true
        self.lock.unlock()
    }
}

/// File and folder transfers for FTP and FTPS. Downloads go to a temporary file and replace the target only on success.
public actor FTPTransferClient: TransferClient {
    private let runner: FTPSessionRunner
    private var storedJobs: [TransferJob] = []
    private var cancellations: [TransferJobID: FTPCancellation] = [:]

    public init(credentialStore: CredentialStore? = nil, hostTrustStore: HostTrustStore? = nil, pinCache: FTPTLSPinCache = FTPTLSPinCache()) {
        self.runner = FTPSessionRunner(credentialStore: credentialStore, hostTrustStore: hostTrustStore, pinCache: pinCache)
    }

    private struct FilePlan {
        var localPath: String
        var remotePath: String
        var size: Int64
    }

    private struct TransferCancelled: Error {}

    public func enqueue(_ job: TransferJob, profile: ServerProfile, onUpdate: (@Sendable (TransferJob) async -> Void)? = nil) async throws {
        var current = job
        current.status = .running(progress: 0, bytesPerSecond: nil)
        current.startedAt = Date()
        self.upsert(current)
        let cancellation = FTPCancellation()
        self.cancellations[job.id] = cancellation
        defer { self.cancellations[job.id] = nil }
        await onUpdate?(current)

        do {
            let plan = try await self.plan(for: job, profile: profile)
            let totalBytes = max(plan.reduce(0) { $0 + $1.size }, 1)
            let progress = FTPProgress()
            let started = Date()
            // The transfer runs on a background thread; this task reports its byte count twice a second.
            let monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await self?.report(job.id, bytes: progress.bytes, totalBytes: totalBytes, started: started, onUpdate: onUpdate)
                }
            }
            defer { monitor.cancel() }
            for file in plan {
                guard !cancellation.isCancelled else { return }
                let done = progress.bytes
                try await self.runner.withConnection(profile) { connection in
                    try Self.transfer(file, direction: job.direction, connection: connection, cancellation: cancellation) { sent in
                        progress.bytes = done + sent
                    }
                }
                progress.bytes = done + file.size
            }
            current.status = .succeeded
        } catch {
            if cancellation.isCancelled { return }
            current.status = .failed(message: Redactor().redact(error.localizedDescription))
        }
        current.finishedAt = Date()
        self.upsert(current)
        await onUpdate?(current)
    }

    private func report(_ id: TransferJobID, bytes: Int64, totalBytes: Int64, started: Date, onUpdate: (@Sendable (TransferJob) async -> Void)?) async {
        guard let index = storedJobs.firstIndex(where: { $0.id == id }), case .running = self.storedJobs[index].status else { return }
        let elapsed = max(Date().timeIntervalSince(started), 0.001)
        self.storedJobs[index].status = .running(progress: min(Double(bytes) / Double(totalBytes), 1), bytesPerSecond: Int64(Double(bytes) / elapsed))
        await onUpdate?(self.storedJobs[index])
    }

    public func cancel(id: TransferJobID) async throws {
        self.cancellations[id]?.cancel()
        guard let index = storedJobs.firstIndex(where: { $0.id == id }) else { return }
        self.storedJobs[index].status = .cancelled
        self.storedJobs[index].finishedAt = Date()
    }

    public func retry(id: TransferJobID) async throws {
        guard let index = storedJobs.firstIndex(where: { $0.id == id }) else { return }
        self.storedJobs[index].status = .queued
        self.storedJobs[index].startedAt = nil
        self.storedJobs[index].finishedAt = nil
    }

    public func jobs() async -> [TransferJob] {
        self.storedJobs
    }

    private func plan(for job: TransferJob, profile: ServerProfile) async throws -> [FilePlan] {
        switch (job.direction, job.isFolder) {
        case (.upload, false):
            let size = (try? FileManager.default.attributesOfItem(atPath: job.sourcePath)[.size] as? NSNumber)?.int64Value ?? 0
            return [FilePlan(localPath: job.sourcePath, remotePath: job.destinationPath, size: size)]
        case (.upload, true):
            return try await self.uploadPlan(localRoot: job.sourcePath, remoteRoot: job.destinationPath, profile: profile)
        case (.download, false):
            return [FilePlan(localPath: job.destinationPath, remotePath: job.sourcePath, size: job.byteCount ?? 0)]
        case (.download, true):
            try FileManager.default.createDirectory(atPath: job.destinationPath, withIntermediateDirectories: true)
            return try await self.downloadPlan(remoteRoot: job.sourcePath, localRoot: job.destinationPath, profile: profile)
        }
    }

    private func uploadPlan(localRoot: String, remoteRoot: String, profile: ServerProfile) async throws -> [FilePlan] {
        let rootURL = URL(fileURLWithPath: NSString(string: localRoot).expandingTildeInPath).standardizedFileURL
        var folders = [remoteRoot]
        var files: [FilePlan] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: keys)
        while let url = enumerator?.nextObject() as? URL {
            let relative = String(url.standardizedFileURL.path.dropFirst(rootURL.path.count + 1))
            let remote = SFTPBatchCommandBuilder.join(remoteRoot, relative)
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true {
                folders.append(remote)
            } else {
                files.append(FilePlan(localPath: url.path, remotePath: remote, size: Int64(values.fileSize ?? 0)))
            }
        }
        let targets = try folders.map { try FTPCommandBuilder.commandPath($0) }
        try await self.runner.withConnection(profile) { connection in
            for target in targets {
                // 550 usually means the folder exists already; a real problem shows when the files go up.
                _ = try connection.send("MKD \(target)")
            }
        }
        return files
    }

    private func downloadPlan(remoteRoot: String, localRoot: String, profile: ServerProfile) async throws -> [FilePlan] {
        var files: [FilePlan] = []
        for item in try await self.runner.list(remoteRoot, profile: profile, showHidden: true) {
            let local = URL(fileURLWithPath: localRoot).appendingPathComponent(item.name).path
            switch item.kind {
            case .folder:
                try FileManager.default.createDirectory(atPath: local, withIntermediateDirectories: true)
                try await files.append(contentsOf: self.downloadPlan(remoteRoot: item.path, localRoot: local, profile: profile))
            case .file, .symbolicLink, .unknown:
                files.append(FilePlan(localPath: local, remotePath: item.path, size: item.size ?? 0))
            }
        }
        return files
    }

    private static func transfer(_ file: FilePlan, direction: TransferDirection, connection: FTPConnection, cancellation: FTPCancellation, progress: (Int64) -> Void) throws {
        let remote = try FTPCommandBuilder.commandPath(file.remotePath)
        let localURL = URL(fileURLWithPath: NSString(string: file.localPath).expandingTildeInPath)
        var chunk = [UInt8](repeating: 0, count: 256 * 1024)
        var moved: Int64 = 0
        switch direction {
        case .upload:
            let input = try FileHandle(forReadingFrom: localURL)
            defer { try? input.close() }
            try connection.transfer("STOR \(remote)") { data in
                while let block = try input.read(upToCount: chunk.count), !block.isEmpty {
                    guard !cancellation.isCancelled else { throw TransferCancelled() }
                    try data.write(block)
                    moved += Int64(block.count)
                    progress(moved)
                }
            }
        case .download:
            let destination = AtomicDownloadDestination(finalURL: localURL)
            let output = try destination.prepare()
            defer { destination.cleanup() }
            do {
                try connection.transfer("RETR \(remote)") { data in
                    while true {
                        guard !cancellation.isCancelled else { throw TransferCancelled() }
                        let count = try chunk.withUnsafeMutableBytes { try data.read(into: $0) }
                        guard count > 0 else { return }
                        try output.write(contentsOf: chunk[0 ..< count])
                        moved += Int64(count)
                        progress(moved)
                    }
                }
                try output.close()
            } catch {
                try? output.close()
                throw error
            }
            try destination.commit()
        }
    }

    private func upsert(_ job: TransferJob) {
        if let index = storedJobs.firstIndex(where: { $0.id == job.id }) {
            self.storedJobs[index] = job
        } else {
            self.storedJobs.append(job)
        }
    }
}

/// Byte count shared between the transfer thread and the actor.
private final class FTPProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 0

    var bytes: Int64 {
        get {
            self.lock.lock()
            defer { lock.unlock() }
            return self.value
        }
        set {
            self.lock.lock()
            self.value = newValue
            self.lock.unlock()
        }
    }
}
