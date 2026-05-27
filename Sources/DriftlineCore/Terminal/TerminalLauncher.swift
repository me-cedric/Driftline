import Foundation

public protocol TerminalLaunching: Sendable {
    func launch(_ command: TerminalCommand) async throws
}

public struct TerminalAppleScriptBuilder: Sendable {
    public init() {}

    public func script(for command: TerminalCommand) -> String {
        let escaped = command.displayString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Terminal"
          activate
          do script "\(escaped)"
        end tell
        """
    }
}

public struct SystemTerminalLauncher: TerminalLaunching {
    private let processExecutor: SystemProcessExecuting
    private let scriptBuilder: TerminalAppleScriptBuilder

    public init(
        processExecutor: SystemProcessExecuting = FoundationProcessExecutor(),
        scriptBuilder: TerminalAppleScriptBuilder = TerminalAppleScriptBuilder()
    ) {
        self.processExecutor = processExecutor
        self.scriptBuilder = scriptBuilder
    }

    public func launch(_ command: TerminalCommand) async throws {
        let script = self.scriptBuilder.script(for: command)
        let result = try await processExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", script], timeout: 15)
        guard result.exitCode == 0 else {
            throw TerminalLaunchError.failed(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

public enum TerminalLaunchError: Error, Equatable, LocalizedError {
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case let .failed(message):
            message.isEmpty ? "Terminal could not be opened." : message
        }
    }
}
