import Foundation

public actor NativeSFTPTransferClient: TransferClient {
    private let credentialStore: CredentialStore
    private let hostTrustStore: HostTrustStore
    private var storedJobs: [TransferJob] = []
    private var activeConnections: [TransferJobID: NativeSFTPConnection] = [:]
    private var cancelled: Set<TransferJobID> = []

    public init(credentialStore: CredentialStore, hostTrustStore: HostTrustStore) {
        self.credentialStore = credentialStore
        self.hostTrustStore = hostTrustStore
    }

    public func enqueue(_ job: TransferJob, profile: ServerProfile, onUpdate: (@Sendable (TransferJob) async -> Void)? = nil) async throws {
        var current = job
        current.status = .running(progress: 0, bytesPerSecond: nil)
        current.startedAt = Date()
        upsert(current)
        await onUpdate?(current)

        let connection = try await NativeSFTPClient.makeConnection(profile: profile, credentialStore: credentialStore, hostTrustStore: hostTrustStore)
        activeConnections[job.id] = connection

        do {
            switch job.direction {
            case .upload:
                try await connection.uploadFile(localPath: job.sourcePath, remotePath: job.destinationPath, jobID: job.id) { [self] progress, speed in
                    await publishRunning(id: job.id, progress: progress, speed: speed, onUpdate: onUpdate)
                } cancellation: { [weakSelf = self] in
                    await weakSelf.isCancelled(job.id)
                }
            case .download:
                try await connection.downloadFile(remotePath: job.sourcePath, localPath: job.destinationPath, jobID: job.id) { [self] progress, speed in
                    await publishRunning(id: job.id, progress: progress, speed: speed, onUpdate: onUpdate)
                } cancellation: { [weakSelf = self] in
                    await weakSelf.isCancelled(job.id)
                }
            }

            if isCancelled(job.id) {
                current.status = .cancelled
            } else {
                current.status = .succeeded
            }
        } catch is CancellationError {
            current.status = .cancelled
        } catch {
            current.status = .failed(message: Redactor().redact(error.localizedDescription))
        }
        activeConnections[job.id] = nil
        await connection.close()
        current.finishedAt = Date()
        upsert(current)
        await onUpdate?(current)
        cancelled.remove(job.id)
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
}
