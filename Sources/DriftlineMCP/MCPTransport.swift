import Foundation

// MARK: - MCPTransport

/// Common lifecycle interface for MCP transports.
public protocol MCPTransport: Sendable {
    /// Run the transport; blocks until stopped (EOF, shutdown, etc.).
    func run() async throws
    /// Request graceful shutdown.
    func stop() async
}

// MARK: - StdioMCPTransport

/// Newline-delimited JSON transport over stdin/stdout.
///
/// Design decisions (per spec):
/// - One dedicated Task reads stdin bytes, accumulates line buffers, and
///   emits complete lines when 0x0A is encountered.
/// - Each `tools/call` runs in a child Task so long transfers don't block
///   `ping` / `tools/list` on the same stream.
/// - All stdout writes are serialised through an actor-isolated writer.
/// - `\r` preceding `\n` is stripped; empty lines are skipped.
/// - EOF from stdin signals graceful shutdown.
public actor StdioMCPTransport: MCPTransport {
    private let engine: MCPEngine
    private var stopped = false
    private var pendingTaskCount = 0

    /// Continuation used to signal shutdown to `run()`.
    private var shutdownContinuation: CheckedContinuation<Void, Never>?

    public init(engine: MCPEngine) {
        self.engine = engine
    }

    public nonisolated func run() async throws {
        await self._run()
    }

    private func _run() async {
        let readerTask = Task<Void, Never> {
            await self.readStdin()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.shutdownContinuation = continuation
        }

        readerTask.cancel()
    }

    public func stop() async {
        self.stopped = true
        if self.pendingTaskCount == 0 {
            self.resume()
        }
    }

    // MARK: - Stdin reader

    private func readStdin() async {
        var lineBuffer: [UInt8] = []
        let stdinHandle = FileHandle.standardInput

        // FileHandle.bytes throws in Swift 6 strict concurrency; handle gracefully.
        do {
            for try await byte in stdinHandle.bytes {
                if self.stopped { break }

                if byte == UInt8(ascii: "\n") {
                    // Strip trailing \r.
                    if lineBuffer.last == UInt8(ascii: "\r") {
                        lineBuffer.removeLast()
                    }
                    if !lineBuffer.isEmpty {
                        let line = lineBuffer
                        lineBuffer = []
                        await self.processLine(Data(line))
                    }
                } else {
                    lineBuffer.append(byte)
                }
            }
        } catch {
            // IO error or task cancelled — fall through to drain.
        }

        // Flush any remaining bytes at EOF.
        if !lineBuffer.isEmpty {
            await self.processLine(Data(lineBuffer))
        }

        self.drainAndShutdown()
    }

    // MARK: - Line processing

    private func processLine(_ data: Data) async {
        guard let value = try? JSONValueDecoder.decode(data) else {
            let response = JSONRPCResponse.parseError()
            await self.writeResponse(response)
            return
        }

        // Fan out tools/call to a child Task so long ops don't head-of-line block.
        if self.isToolsCall(value) {
            self.pendingTaskCount += 1
            Task {
                let response = await self.engine.handle(value)
                if let response {
                    await self.writeResponse(response)
                }
                self.decrementPending()
            }
        } else {
            let response = await engine.handle(value)
            if let response {
                await self.writeResponse(response)
            }
        }
    }

    private func isToolsCall(_ value: JSONValue) -> Bool {
        value["method"]?.stringValue == "tools/call"
    }

    // MARK: - Stdout writer (serialised by actor isolation)

    private func writeResponse(_ value: JSONValue) async {
        guard let data = try? JSONValueEncoder.encode(value) else { return }
        var lineData = data
        lineData.append(0x0a) // \n
        FileHandle.standardOutput.write(lineData)
    }

    // MARK: - Pending task tracking

    private func decrementPending() {
        self.pendingTaskCount -= 1
        if self.stopped, self.pendingTaskCount == 0 {
            self.resume()
        }
    }

    private func drainAndShutdown() {
        self.stopped = true
        if self.pendingTaskCount == 0 {
            self.resume()
        }
        // Otherwise resume() is called from decrementPending() once last task finishes.
    }

    private func resume() {
        self.shutdownContinuation?.resume()
        self.shutdownContinuation = nil
    }
}
