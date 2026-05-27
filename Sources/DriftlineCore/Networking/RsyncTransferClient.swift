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

        let multiplier: Double
        switch chunk[unitRange].lowercased() {
        case "kb": multiplier = 1000
        case "mb": multiplier = 1_000_000
        case "gb": multiplier = 1_000_000_000
        default: multiplier = 1
        }
        return Int64(value * multiplier)
    }
}

public enum RsyncCommandBuilder {
    public static func arguments(for job: TransferJob, profile: ServerProfile) throws -> [String] {
        let sshArguments = try SSHCommandBuilder.baseArguments(for: profile)
        let sshCommand = (["ssh"] + sshArguments).map(TerminalCommand.shellEscaped).joined(separator: " ")
        var arguments = ["-az", "--progress", "--human-readable", "-e", sshCommand]

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
}

public actor SystemRsyncTransferClient: TransferClient {
    private let streamingExecutor: StreamingProcessExecuting
    private let cancellableExecutor: CancellableStreamingProcessExecuting?
    private var storedJobs: [TransferJob] = []

    public init(streamingExecutor: StreamingProcessExecuting = FoundationStreamingProcessExecutor()) {
        self.streamingExecutor = streamingExecutor
        self.cancellableExecutor = streamingExecutor as? CancellableStreamingProcessExecuting
    }

    public func enqueue(_ job: TransferJob, profile: ServerProfile, onUpdate: (@Sendable (TransferJob) async -> Void)? = nil) async throws {
        var current = job
        current.status = .running(progress: 0, bytesPerSecond: nil)
        current.startedAt = Date()
        self.upsert(current)
        await onUpdate?(current)

        let arguments = try RsyncCommandBuilder.arguments(for: job, profile: profile)
        for try await event in self.streamingExecutor.stream(executable: "/usr/bin/rsync", arguments: arguments, timeout: 60 * 60) {
            switch event {
            case let .standardOutput(chunk), let .standardError(chunk):
                if let parsed = RsyncProgressParser.progress(from: chunk) {
                    current.status = .running(progress: parsed.progress, bytesPerSecond: parsed.bytesPerSecond)
                    self.upsert(current)
                    await onUpdate?(current)
                }
            case let .finished(result):
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
        }
    }

    public func cancel(id: TransferJobID) async throws {
        await self.cancellableExecutor?.cancelAll()
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
