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
    func run(executable: String, arguments: [String], environment: [String: String], standardInput: Data?, timeout: TimeInterval) async throws -> ProcessResult
}

public extension SystemProcessExecuting {
    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        try await self.run(executable: executable, arguments: arguments, environment: [:], standardInput: nil, timeout: timeout)
    }
}

public struct FoundationProcessExecutor: SystemProcessExecuting {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        standardInput: Data? = nil,
        timeout: TimeInterval = 30
    ) async throws -> ProcessResult {
        let process = Process()
        let handle = ProcessHandle(process)
        // A cancelled caller (for example a server probe while the user types) stops its process at once.
        return try await withTaskCancellationHandler {
            try await self.launch(process, executable: executable, arguments: arguments, environment: environment, input: (standardInput, timeout))
        } onCancel: {
            handle.terminate()
        }
    }

    private func launch(
        _ process: Process,
        executable: String,
        arguments: [String],
        environment: [String: String],
        input: (standardInput: Data?, timeout: TimeInterval)
    ) async throws -> ProcessResult {
        let (standardInput, timeout) = input
        return try await withCheckedThrowingContinuation { continuation in
            let stdout = Pipe()
            let stderr = Pipe()
            let stdin = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if !environment.isEmpty {
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
            }
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = standardInput == nil ? FileHandle.nullDevice : stdin

            let resumeState = ProcessResumeState()
            let output = ProcessOutputBuffer()
            let completion = DispatchGroup()

            @Sendable func resume(_ result: Result<ProcessResult, Error>) {
                guard resumeState.markResumedIfNeeded() else { return }
                switch result {
                case let .success(value):
                    continuation.resume(returning: value)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            completion.enter()
            process.terminationHandler = { _ in completion.leave() }

            do {
                try process.run()
            } catch {
                resume(.failure(error))
                return
            }

            // Drain both pipes while the process runs: a full pipe buffer (64 KB) would block the child forever.
            completion.enter()
            DispatchQueue.global().async {
                output.standardOutput = stdout.fileHandleForReading.readDataToEndOfFile()
                completion.leave()
            }
            completion.enter()
            DispatchQueue.global().async {
                output.standardError = stderr.fileHandleForReading.readDataToEndOfFile()
                completion.leave()
            }
            if let standardInput {
                DispatchQueue.global().async {
                    let handle = stdin.fileHandleForWriting
                    _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
                    try? handle.write(contentsOf: standardInput)
                    try? handle.close()
                }
            }

            completion.notify(queue: .global()) {
                resume(.success(ProcessResult(
                    exitCode: process.terminationStatus,
                    standardOutput: String(data: output.standardOutput, encoding: .utf8) ?? "",
                    standardError: String(data: output.standardError, encoding: .utf8) ?? ""
                )))
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

private final class ProcessHandle: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        if self.process.isRunning {
            self.process.terminate()
        }
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    var standardOutput = Data()
    var standardError = Data()
}

private final class ProcessResumeState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func markResumedIfNeeded() -> Bool {
        self.lock.lock()
        defer { lock.unlock() }
        guard !self.didResume else { return false }
        self.didResume = true
        return true
    }
}
