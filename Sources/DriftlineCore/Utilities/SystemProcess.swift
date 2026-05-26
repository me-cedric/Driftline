import Foundation

public struct ProcessResult: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol SystemProcessExecuting: Sendable {
    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult
}

public struct FoundationProcessExecutor: SystemProcessExecuting {
    public init() {}

    public func run(executable: String, arguments: [String], timeout: TimeInterval = 30) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr

            let resumeState = ProcessResumeState()

            @Sendable func resume(_ result: Result<ProcessResult, Error>) {
                guard resumeState.markResumedIfNeeded() else { return }
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            process.terminationHandler = { terminated in
                let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                resume(.success(ProcessResult(exitCode: terminated.terminationStatus, standardOutput: output, standardError: error)))
            }

            do {
                try process.run()
            } catch {
                resume(.failure(error))
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                    resume(.success(ProcessResult(exitCode: 124, standardOutput: "", standardError: "Command timed out.")))
                }
            }
        }
    }
}

private final class ProcessResumeState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func markResumedIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}
