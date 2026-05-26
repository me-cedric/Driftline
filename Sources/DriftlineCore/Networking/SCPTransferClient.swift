import Foundation

public enum TransferCommandBuilder {
    public static func scpArguments(for job: TransferJob, profile: ServerProfile) throws -> [String] {
        var arguments = try SSHCommandBuilder.baseArguments(for: profile)
        arguments.removeFirst(2) // scp uses -P instead of ssh's -p.
        arguments.insert(contentsOf: ["-P", String(profile.port)], at: 0)

        if isLikelyDirectory(path: job.sourcePath) {
            arguments.append("-r")
        }

        switch job.direction {
        case .upload:
            arguments.append(NSString(string: job.sourcePath).expandingTildeInPath)
            arguments.append("\(profile.username)@\(profile.host):\(SSHCommandBuilder.shellSingleQuoted(job.destinationPath))")
        case .download:
            arguments.append("\(profile.username)@\(profile.host):\(SSHCommandBuilder.shellSingleQuoted(job.sourcePath))")
            arguments.append(NSString(string: job.destinationPath).expandingTildeInPath)
        }
        return arguments
    }

    private static func isLikelyDirectory(path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: NSString(string: path).expandingTildeInPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

public actor SystemSCPTransferClient: TransferClient {
    private let processExecutor: SystemProcessExecuting
    private var storedJobs: [TransferJob] = []

    public init(processExecutor: SystemProcessExecuting = FoundationProcessExecutor()) {
        self.processExecutor = processExecutor
    }

    public func enqueue(_ job: TransferJob, profile: ServerProfile, onUpdate: (@Sendable (TransferJob) async -> Void)? = nil) async throws {
        var running = job
        running.status = .running(progress: 0, bytesPerSecond: nil)
        running.startedAt = Date()
        upsert(running)
        await onUpdate?(running)

        let arguments = try TransferCommandBuilder.scpArguments(for: job, profile: profile)
        let result = try await processExecutor.run(executable: "/usr/bin/scp", arguments: arguments, timeout: 60 * 60)

        var finished = running
        finished.finishedAt = Date()
        if result.exitCode == 0 {
            finished.status = .succeeded
        } else {
            let message = Redactor().redact(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
            finished.status = .failed(message: message.isEmpty ? "Transfer failed." : message)
        }
        upsert(finished)
        await onUpdate?(finished)
    }

    public func cancel(id: TransferJobID) async throws {
        guard let index = storedJobs.firstIndex(where: { $0.id == id }) else { return }
        storedJobs[index].status = .cancelled
        storedJobs[index].finishedAt = Date()
    }

    public func retry(id: TransferJobID) async throws {
        guard let index = storedJobs.firstIndex(where: { $0.id == id }) else { return }
        storedJobs[index].status = .queued
        storedJobs[index].startedAt = nil
        storedJobs[index].finishedAt = nil
    }

    public func jobs() async -> [TransferJob] {
        storedJobs
    }

    private func upsert(_ job: TransferJob) {
        if let index = storedJobs.firstIndex(where: { $0.id == job.id }) {
            storedJobs[index] = job
        } else {
            storedJobs.append(job)
        }
    }
}
