import Foundation

struct BandwidthThrottle {
    let bytesPerSecondLimit: Int64

    func delay(bytesSent: Int64, elapsed: TimeInterval) -> TimeInterval {
        guard elapsed > 0 else { return 0 }
        let expected = Double(bytesSent) / Double(self.bytesPerSecondLimit)
        return max(0, expected - elapsed)
    }
}

public actor NativeSFTPTransferClient: TransferClient {
    private let credentialStore: CredentialStore
    private let hostTrustStore: HostTrustStore
    public let bytesPerSecondLimit: Int64?
    private var storedJobs: [TransferJob] = []
    private var activeConnections: [TransferJobID: NativeSFTPConnection] = [:]
    private var cancelled: Set<TransferJobID> = []

    public init(credentialStore: CredentialStore, hostTrustStore: HostTrustStore, bytesPerSecondLimit: Int64? = nil) {
        self.credentialStore = credentialStore
        self.hostTrustStore = hostTrustStore
        self.bytesPerSecondLimit = bytesPerSecondLimit
    }

    public func enqueue(_ job: TransferJob, profile: ServerProfile, onUpdate: (@Sendable (TransferJob) async -> Void)? = nil) async throws {
        var current = job
        current.status = .running(progress: 0, bytesPerSecond: nil)
        current.startedAt = Date()
        self.upsert(current)
        await onUpdate?(current)

        let connection = try await NativeSFTPClient.makeConnection(profile: profile, credentialStore: self.credentialStore, hostTrustStore: self.hostTrustStore)
        self.activeConnections[job.id] = connection

        let throttle = self.bytesPerSecondLimit.map { BandwidthThrottle(bytesPerSecondLimit: $0) }
        let transferStart = Date()
        var caughtError: Error?

        do {
            if job.isFolder {
                switch job.direction {
                case .upload:
                    try await connection.uploadFolder(localPath: job.sourcePath, remotePath: job.destinationPath, jobID: job.id) { [self] progress, speed in
                        await self.applyThrottle(throttle, progress: progress, byteCount: job.byteCount, transferStart: transferStart)
                        await self.publishRunning(id: job.id, progress: progress, speed: speed, onUpdate: onUpdate)
                    } cancellation: { [weakSelf = self] in
                        await weakSelf.isCancelled(job.id)
                    }
                case .download:
                    try await connection.downloadFolder(remotePath: job.sourcePath, localPath: job.destinationPath, jobID: job.id) { [self] progress, speed in
                        await self.applyThrottle(throttle, progress: progress, byteCount: job.byteCount, transferStart: transferStart)
                        await self.publishRunning(id: job.id, progress: progress, speed: speed, onUpdate: onUpdate)
                    } cancellation: { [weakSelf = self] in
                        await weakSelf.isCancelled(job.id)
                    }
                }
            } else {
                switch job.direction {
                case .upload:
                    try await connection.uploadFile(localPath: job.sourcePath, remotePath: job.destinationPath, jobID: job.id) { [self] progress, speed in
                        await self.applyThrottle(throttle, progress: progress, byteCount: job.byteCount, transferStart: transferStart)
                        await self.publishRunning(id: job.id, progress: progress, speed: speed, onUpdate: onUpdate)
                    } cancellation: { [weakSelf = self] in
                        await weakSelf.isCancelled(job.id)
                    }
                case .download:
                    try await connection.downloadFile(remotePath: job.sourcePath, localPath: job.destinationPath, jobID: job.id) { [self] progress, speed in
                        await self.applyThrottle(throttle, progress: progress, byteCount: job.byteCount, transferStart: transferStart)
                        await self.publishRunning(id: job.id, progress: progress, speed: speed, onUpdate: onUpdate)
                    } cancellation: { [weakSelf = self] in
                        await weakSelf.isCancelled(job.id)
                    }
                }
            }

            if self.isCancelled(job.id) {
                current.status = .cancelled
            } else {
                current.status = .succeeded
            }
        } catch is CancellationError {
            current.status = .cancelled
            caughtError = CancellationError()
        } catch {
            current.status = .failed(message: Redactor().redact(error.localizedDescription))
            caughtError = error
        }
        self.activeConnections[job.id] = nil
        await connection.close()
        current.finishedAt = Date()
        self.upsert(current)
        await onUpdate?(current)
        self.cancelled.remove(job.id)
        if let caughtError {
            throw caughtError
        }
    }

    public func cancel(id: TransferJobID) async throws {
        self.cancelled.insert(id)
        await self.activeConnections[id]?.close()
        guard let index = storedJobs.firstIndex(where: { $0.id == id }) else { return }
        self.storedJobs[index].status = .cancelled
        self.storedJobs[index].finishedAt = Date()
    }

    public func retry(id: TransferJobID) async throws {
        self.cancelled.remove(id)
        guard let index = storedJobs.firstIndex(where: { $0.id == id }) else { return }
        self.storedJobs[index].status = .queued
        self.storedJobs[index].startedAt = nil
        self.storedJobs[index].finishedAt = nil
    }

    public func jobs() async -> [TransferJob] {
        self.storedJobs
    }

    private func publishRunning(
        id: TransferJobID,
        progress: Double,
        speed: Int64?,
        onUpdate: (@Sendable (TransferJob) async -> Void)?
    ) async {
        guard var job = storedJobs.first(where: { $0.id == id }) else { return }
        job.status = .running(progress: progress, bytesPerSecond: speed)
        self.upsert(job)
        await onUpdate?(job)
    }

    private func isCancelled(_ id: TransferJobID) -> Bool {
        self.cancelled.contains(id)
    }

    private func upsert(_ job: TransferJob) {
        if let index = storedJobs.firstIndex(where: { $0.id == job.id }) {
            self.storedJobs[index] = job
        } else {
            self.storedJobs.append(job)
        }
    }

    private func applyThrottle(_ throttle: BandwidthThrottle?, progress: Double, byteCount: Int64?, transferStart: Date) async {
        guard let throttle else { return }
        let bytesSent = Int64(progress * Double(byteCount ?? 0))
        let elapsed = Date().timeIntervalSince(transferStart)
        let wait = throttle.delay(bytesSent: bytesSent, elapsed: elapsed)
        if wait > 0.001 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }
}
