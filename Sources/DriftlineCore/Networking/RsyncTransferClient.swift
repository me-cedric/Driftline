import Foundation

public enum RsyncProgressParser {
    private static let percentRegex = try? NSRegularExpression(pattern: #"(?m)(\d{1,3})%"#)
    private static let speedRegex = try? NSRegularExpression(pattern: #"(?m)\s([0-9]+(?:\.[0-9]+)?)([kKmMgG]?B)/s"#)

    public static func progress(from chunk: String) -> (progress: Double, bytesPerSecond: Int64?)? {
        let range = NSRange(chunk.startIndex ..< chunk.endIndex, in: chunk)
        guard let percentMatch = percentRegex?.matches(in: chunk, range: range).last,
              let percentRange = Range(percentMatch.range(at: 1), in: chunk),
              let percent = Double(chunk[percentRange])
        else { return nil }

        let speed = self.parseSpeed(from: chunk)
        return (min(max(percent / 100, 0), 1), speed)
    }

    private static func parseSpeed(from chunk: String) -> Int64? {
        let range = NSRange(chunk.startIndex ..< chunk.endIndex, in: chunk)
        guard let match = speedRegex?.matches(in: chunk, range: range).last,
              let valueRange = Range(match.range(at: 1), in: chunk),
              let unitRange = Range(match.range(at: 2), in: chunk),
              let value = Double(chunk[valueRange])
        else { return nil }

        let multiplier: Double = switch chunk[unitRange].lowercased() {
        case "kb": 1000
        case "mb": 1_000_000
        case "gb": 1_000_000_000
        default: 1
        }
        return Int64(value * multiplier)
    }
}

public enum RsyncCommandBuilder {
    /// rsync needs a remote shell and a remote rsync binary. Exit 12 alone can also be a dropped connection, so the message decides.
    public static func remoteRsyncIsMissing(_ result: ProcessResult) -> Bool {
        let error = result.standardError.lowercased()
        let missing = ["command not found", "rsync: not found", "sftp connections only", "this service allows sftp"]
        return result.exitCode != 0 && (result.exitCode == 127 || missing.contains(where: error.contains))
    }

    public static func arguments(for job: TransferJob, profile: ServerProfile) throws -> [String] {
        let sshArguments = try SSHCommandBuilder.baseArguments(for: profile)
        let sshCommand = (["ssh"] + sshArguments).map(TerminalCommand.shellEscaped).joined(separator: " ")
        var arguments = ["-az", "--progress", "--human-readable", "-e", sshCommand]
        // A trailing slash copies the folder contents into the destination path, instead of a nested folder inside it.
        let folderSuffix = job.isFolder ? "/" : ""

        switch job.direction {
        case .upload:
            arguments.append(NSString(string: job.sourcePath).expandingTildeInPath + folderSuffix)
            arguments.append("\(profile.username)@\(profile.host):\(SSHCommandBuilder.shellSingleQuoted(job.destinationPath))")
        case .download:
            arguments.append("\(profile.username)@\(profile.host):\(SSHCommandBuilder.shellSingleQuoted(job.sourcePath + folderSuffix))")
            arguments.append(NSString(string: job.destinationPath).expandingTildeInPath)
        }
        return arguments
    }
}

public actor SystemRsyncTransferClient: TransferClient {
    private let streamingExecutor: StreamingProcessExecuting
    private let credentialStore: CredentialStore?
    private var storedJobs: [TransferJob] = []
    /// The process of each running job. Cancelling the task ends the stream, and the stream ends its process.
    private var runningTasks: [TransferJobID: Task<ProcessResult, Error>] = [:]

    public init(streamingExecutor: StreamingProcessExecuting = FoundationStreamingProcessExecutor(), credentialStore: CredentialStore? = nil) {
        self.streamingExecutor = streamingExecutor
        self.credentialStore = credentialStore
    }

    public func enqueue(_ job: TransferJob, profile: ServerProfile, onUpdate: (@Sendable (TransferJob) async -> Void)? = nil) async throws {
        var current = job
        current.status = .running(progress: 0, bytesPerSecond: nil)
        current.startedAt = Date()
        self.upsert(current)
        await onUpdate?(current)

        let arguments = try RsyncCommandBuilder.arguments(for: job, profile: profile)
        let askPass = try await SSHAskPassSession.make(for: profile, credentialStore: self.credentialStore)
        defer { askPass?.close() }
        var result = try await self.runStreaming("/usr/bin/rsync", arguments: arguments, environment: askPass?.environment ?? [:], job: current, onUpdate: onUpdate)
        if self.isCancelled(job.id) { return }
        if RsyncCommandBuilder.remoteRsyncIsMissing(result) {
            // SFTP-only servers have no remote shell or rsync. The SFTP subsystem still works.
            result = try await self.runSFTPTransfer(current, profile: profile, onUpdate: onUpdate)
            if self.isCancelled(job.id) { return }
        }

        current.finishedAt = Date()
        if result.exitCode == 0 {
            current.status = .succeeded
        } else {
            let message = Redactor().redact(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
            current.status = .failed(message: message.isEmpty ? "Transfer failed." : message)
        }
        self.upsert(current)
        await onUpdate?(current)
    }

    private func runSFTPTransfer(_ job: TransferJob, profile: ServerProfile, onUpdate: (@Sendable (TransferJob) async -> Void)?) async throws -> ProcessResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("driftline-sftp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let batchURL = directory.appendingPathComponent("batch")
        let commands = try SFTPBatchCommandBuilder.transferCommand(direction: job.direction, sourcePath: job.sourcePath, destinationPath: job.destinationPath, isFolder: job.isFolder)
        try commands.write(to: batchURL, atomically: true, encoding: .utf8)
        let arguments = try SSHCommandBuilder.sftpBatchArguments(for: profile, batchFile: batchURL.path)
        let askPass = try await SSHAskPassSession.make(for: profile, credentialStore: self.credentialStore)
        defer { askPass?.close() }
        return try await self.runStreaming("/usr/bin/sftp", arguments: arguments, environment: askPass?.environment ?? [:], job: job, onUpdate: onUpdate)
    }

    private func runStreaming(
        _ executable: String,
        arguments: [String],
        environment: [String: String],
        job: TransferJob,
        onUpdate: (@Sendable (TransferJob) async -> Void)?
    ) async throws -> ProcessResult {
        let events = self.streamingExecutor.stream(executable: executable, arguments: arguments, environment: environment, timeout: 60 * 60)
        let task = Task { () throws -> ProcessResult in
            var current = job
            var finalResult = ProcessResult(exitCode: 1, standardOutput: "", standardError: "Transfer ended without a result.")
            for try await event in events {
                switch event {
                case let .standardOutput(chunk), let .standardError(chunk):
                    if let parsed = RsyncProgressParser.progress(from: chunk), !self.isCancelled(job.id) {
                        current.status = .running(progress: parsed.progress, bytesPerSecond: parsed.bytesPerSecond)
                        self.upsert(current)
                        await onUpdate?(current)
                    }
                case let .finished(result):
                    finalResult = result
                }
            }
            return finalResult
        }
        self.runningTasks[job.id] = task
        defer { self.runningTasks[job.id] = nil }
        return try await task.value
    }

    private func isCancelled(_ id: TransferJobID) -> Bool {
        self.storedJobs.first { $0.id == id }?.status == .cancelled
    }

    public func cancel(id: TransferJobID) async throws {
        self.runningTasks[id]?.cancel()
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

    private func upsert(_ job: TransferJob) {
        if let index = storedJobs.firstIndex(where: { $0.id == job.id }) {
            self.storedJobs[index] = job
        } else {
            self.storedJobs.append(job)
        }
    }
}
