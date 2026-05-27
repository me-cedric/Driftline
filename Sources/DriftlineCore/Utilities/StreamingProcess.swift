import Foundation

public enum ProcessOutputEvent: Sendable, Equatable {
    case standardOutput(String)
    case standardError(String)
    case finished(ProcessResult)
}

public protocol StreamingProcessExecuting: Sendable {
    func stream(executable: String, arguments: [String], timeout: TimeInterval) -> AsyncThrowingStream<ProcessOutputEvent, Error>
}

public protocol CancellableStreamingProcessExecuting: StreamingProcessExecuting {
    func cancelAll() async
}

public struct FoundationStreamingProcessExecutor: CancellableStreamingProcessExecuting {
    private let registry: StreamingProcessRegistry

    public init(registry: StreamingProcessRegistry = StreamingProcessRegistry()) {
        self.registry = registry
    }

    public func stream(executable: String, arguments: [String], timeout: TimeInterval = 60 * 60) -> AsyncThrowingStream<ProcessOutputEvent, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let state = StreamingProcessState()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                continuation.yield(.standardOutput(chunk))
                state.appendOutput(chunk)
            }

            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                continuation.yield(.standardError(chunk))
                state.appendError(chunk)
            }

            process.terminationHandler = { terminated in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                let result = ProcessResult(
                    exitCode: terminated.terminationStatus,
                    standardOutput: state.output,
                    standardError: state.error
                )
                continuation.yield(.finished(result))
                continuation.finish()
            }

            continuation.onTermination = { _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
                Task { await self.registry.add(process) }
            } catch {
                continuation.finish(throwing: error)
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    public func cancelAll() async {
        await self.registry.cancelAll()
    }
}

public actor StreamingProcessRegistry {
    private var processes: [Process] = []

    public init() {}

    func add(_ process: Process) {
        self.processes.append(process)
    }

    public func cancelAll() {
        for process in self.processes where process.isRunning {
            process.terminate()
        }
        self.processes.removeAll { !$0.isRunning }
    }
}

private final class StreamingProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = ""
    private var stderr = ""

    var output: String {
        self.lock.lock()
        defer { lock.unlock() }
        return self.stdout
    }

    var error: String {
        self.lock.lock()
        defer { lock.unlock() }
        return self.stderr
    }

    func appendOutput(_ value: String) {
        self.lock.lock()
        self.stdout += value
        self.lock.unlock()
    }

    func appendError(_ value: String) {
        self.lock.lock()
        self.stderr += value
        self.lock.unlock()
    }
}
