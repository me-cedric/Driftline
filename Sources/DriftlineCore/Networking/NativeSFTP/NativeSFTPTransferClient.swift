import Foundation

struct BandwidthThrottle: Sendable {
    let bytesPerSecondLimit: Int64

    func delay(bytesSent: Int64, elapsed: TimeInterval) -> TimeInterval {
        guard elapsed > 0 else { return 0 }
        let expected = Double(bytesSent) / Double(bytesPerSecondLimit)
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
        upsert(current)
        await onUpdate?(current)

        let connection = try await NativeSFTPClient.makeConnection(profile: profile, credentialStore: credentialStore, hostTrustStore: hostTrustStore)
        activeConnections[job.id] = connection

        let throttle = bytesPerSecondLimit.map { BandwidthThrottle(bytesPerSecondLimit: $0) }
        let transferStart = Date()
        var caughtError: Error?

        do {
            if job.isFolder {
                switch job.direction {
                case .upload:
                    try await connection.uploadFolder(localPath: job.sourcePath, remotePath: job.destinationPath, jobID: job.id) { [self] progress, speed in
                        await applyThrottle(throttle, progress: progress, byteCount: job.byteCount, transferStart: transferStart)
                        await publishRunning(id: job.id, progress: progress, speed: speed, onUpdate: onUpdate)
                    } cancellation: { [weakSelf = self] in
                        await weakSelf.isCancelled(job.id)
                    }
                case .download:
                    try await connection.downloadFolder(remotePath: job.sourcePath, localPath: job.destinationPath, jobID: job.id) { [self] progress, speed in
                        await applyThrottle(throttle, progress: progress, byteCount: job.byteCount, transferStart: transferStart)
                        await publishRunning(id: job.id, progress: progress, speed: speed, onUpdate: onUpdate)
                    } cancellation: { [weakSelf = self] in
                        await weakSelf.isCancelled(job.id)
                    }
                }
            } else {
                switch job.direction {
                case .upload:
                    try await connection.uploadFile(localPath: job.sourcePath, remotePath: job.destinationPath, jobID: job.id) { [self] progress, speed in
                        await applyThrottle(throttle, progress: progress, byteCount: job.byteCount, transferStart: transferStart)
                        await publishRunning(id: job.id, progress: progress, speed: speed, onUpdate: onUpdate)
                    } cancellation: { [weakSelf = self] in
                        await weakSelf.isCancelled(job.id)
                    }
                case .download:
                    try await connection.downloadFile(remotePath: job.sourcePath, localPath: job.destinationPath, jobID: job.id) { [self] progress, speed in
                        await applyThrottle(throttle, progress: progress, byteCount: job.byteCount, transferStart: transferStart)
                        await publishRunning(id: job.id, progress: progress, speed: speed, onUpdate: onUpdate)
                    } cancellation: { [weakSelf = self] in
                        await weakSelf.isCancelled(job.id)
                    }
                }
            }

            if isCancelled(job.id) {
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
        activeConnections[job.id] = nil
        await connection.close()
        current.finishedAt = Date()
        upsert(current)
        await onUpdate?(current)
        cancelled.remove(job.id)
        if let caughtError {
            throw caughtError
        }
    }

    public func cancel(id: TransferJobID) async throws {
        cancelled.insert(id)
        await activeConnections[id]?.close()
        guard let index = storedJobs.firstIndex(where: { $0.id == id }) else { return }
        storedJobs[index].status = .cancelled
        storedJobs[index].finishedAt = Date()
    }

    public func retry(id: TransferJobID) async throws {
        cancelled.remove(id)
        guard let index = storedJobs.firstIndex(where: { $0.id == id }) else { return }
        storedJobs[index].status = .queued
        storedJobs[index].startedAt = nil
        storedJobs[index].finishedAt = nil
    }

    public func jobs() async -> [TransferJob] {
        storedJobs
    }

    private func publishRunning(
        id: TransferJobID,
        progress: Double,
        speed: Int64?,
        onUpdate: (@Sendable (TransferJob) async -> Void)?
    ) async {
        guard var job = storedJobs.first(where: { $0.id == id }) else { return }
        job.status = .running(progress: progress, bytesPerSecond: speed)
        upsert(job)
        await onUpdate?(job)
    }

    private func isCancelled(_ id: TransferJobID) -> Bool {
        cancelled.contains(id)
    }

    private func upsert(_ job: TransferJob) {
        if let index = storedJobs.firstIndex(where: { $0.id == job.id }) {
            storedJobs[index] = job
        } else {
            storedJobs.append(job)
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
