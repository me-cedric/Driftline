import DriftlineCore
import DriftlineMCP
import Foundation

let version = "0.6.0"
let arguments = Array(CommandLine.arguments.dropFirst())

func printHelp() {
    print("""
    Driftline CLI \(version)

    Usage:
      driftline [path]
      driftline --open [path]
      driftline --bookmark <name>
      driftline --new-tab [path]
      driftline mcp --status
      driftline mcp --enable | --disable
      driftline mcp --allow-destructive | --deny-destructive
      driftline mcp --http-enable | --http-disable [--port <port>]
      driftline mcp --add-root <path> | --remove-root <path>
      driftline mcp --print-config
      driftline --version
      driftline --help

    Notes:
      Secrets are never accepted as CLI arguments.
      The CLI records a local open request and launches Driftline.app when installed or built.
    """)
}

if arguments.first == "mcp" {
    await handleMCPCommand(Array(arguments.dropFirst()))
} else if arguments.contains("--help") || arguments.contains("-h") {
    printHelp()
} else if arguments.contains("--version") {
    print(version)
} else if arguments.contains(where: { $0 == "--password" || $0 == "--passphrase" || $0 == "--secret" }) {
    fputs("driftline: secrets are not accepted on the command line\n", stderr)
    exit(2)
} else {
    let openInNewTab = arguments.contains("--new-tab")
    let request: CLIRequest
    let launchArgument: LaunchArgument
    if let bookmarkName = bookmarkArgument(in: arguments) {
        request = CLIRequest(intent: .openBookmark(bookmarkName), openInNewTab: openInNewTab)
        launchArgument = .bookmark(bookmarkName)
    } else {
        let path = pathArgument(in: arguments) ?? FileManager.default.currentDirectoryPath
        let resolvedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        request = CLIRequest(localPath: resolvedPath, openInNewTab: openInNewTab)
        launchArgument = .path(resolvedPath)
    }
    do {
        try CLIRequestStore.save(request)
        try launchDriftline(argument: launchArgument, newTab: request.openInNewTab)
        print(launchArgument.message)
    } catch {
        fputs("driftline: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

func handleMCPCommand(_ args: [String]) async {
    let command = MCPCommand(arguments: args)
    switch command {
    case .help:
        print("""
        Usage:
          driftline mcp --status
          driftline mcp --enable | --disable
          driftline mcp --allow-destructive | --deny-destructive
          driftline mcp --http-enable | --http-disable [--port <port>]
          driftline mcp --add-root <path> | --remove-root <path>
          driftline mcp --print-config
        """)
    case .printConfig:
        printClientConfig()
    case .unknown:
        fputs("driftline: unknown mcp command\n", stderr)
        exit(2)
    case .status:
        do {
            let config = try await JSONMCPSettingsRepository().load()
            printStatus(config)
        } catch {
            fputs("driftline: \(Redactor().redact(error.localizedDescription))\n", stderr)
            exit(1)
        }
    default:
        await applyMCPMutation(command)
    }
}

func applyMCPMutation(_ command: MCPCommand) async {
    let repository = JSONMCPSettingsRepository()
    do {
        var config = try await repository.load()
        let message = mutateMCPConfiguration(&config, command: command)
        try await repository.save(config)
        print(message)
    } catch {
        fputs("driftline: \(Redactor().redact(error.localizedDescription))\n", stderr)
        exit(1)
    }
}

func mutateMCPConfiguration(_ config: inout MCPServerConfiguration, command: MCPCommand) -> String {
    switch command {
    case .enable, .disable:
        return mutateMCPEnabled(&config, command: command)
    case .allowDestructive, .denyDestructive:
        return mutateMCPDestructive(&config, command: command)
    case let .enableHTTP(port):
        config.httpEnabled = true
        config.bindLoopbackOnly = true
        if let port {
            config.httpPort = port
        }
        return "MCP HTTP enabled on 127.0.0.1:\(config.httpPort)"
    case .disableHTTP:
        config.httpEnabled = false
        return "MCP HTTP disabled"
    case let .addRoot(root):
        let path = URL(fileURLWithPath: root).standardizedFileURL.path
        if !config.allowedLocalRoots.contains(path) {
            config.allowedLocalRoots.append(path)
        }
        return "Added MCP root \(path)"
    case let .removeRoot(root):
        let path = URL(fileURLWithPath: root).standardizedFileURL.path
        config.allowedLocalRoots.removeAll { URL(fileURLWithPath: $0).standardizedFileURL.path == path }
        return "Removed MCP root \(path)"
    case .help, .printConfig, .status, .unknown:
        return ""
    }
}

func mutateMCPEnabled(_ config: inout MCPServerConfiguration, command: MCPCommand) -> String {
    config.enabled = command == .enable
    return config.enabled ? "MCP enabled" : "MCP disabled"
}

func mutateMCPDestructive(_ config: inout MCPServerConfiguration, command: MCPCommand) -> String {
    config.allowDestructiveOperations = command == .allowDestructive
    return config.allowDestructiveOperations ? "MCP destructive operations enabled" : "MCP destructive operations disabled"
}

enum MCPCommand {
    case help
    case status
    case enable
    case disable
    case allowDestructive
    case denyDestructive
    case enableHTTP(Int?)
    case disableHTTP
    case addRoot(String)
    case removeRoot(String)
    case printConfig
    case unknown

    init(arguments: [String]) {
        if arguments.isEmpty || arguments.contains("--help") {
            self = .help
        } else if let root = value(after: "--add-root", in: arguments) {
            self = .addRoot(root)
        } else if let root = value(after: "--remove-root", in: arguments) {
            self = .removeRoot(root)
        } else if arguments.contains("--http-enable") {
            self = .enableHTTP(portArgument(in: arguments))
        } else {
            self = Self.simpleCommand(arguments: arguments)
        }
    }

    private static func simpleCommand(arguments: [String]) -> MCPCommand {
        if arguments.contains("--status") { return .status }
        if arguments.contains("--enable") { return .enable }
        if arguments.contains("--disable") { return .disable }
        if arguments.contains("--allow-destructive") { return .allowDestructive }
        if arguments.contains("--deny-destructive") { return .denyDestructive }
        if arguments.contains("--http-disable") { return .disableHTTP }
        if arguments.contains("--print-config") { return .printConfig }
        return .unknown
    }
}

extension MCPCommand: Equatable {}

func printStatus(_ config: MCPServerConfiguration) {
    let roots = config.allowedLocalRoots.isEmpty ? ["~/Downloads"] : config.allowedLocalRoots
    print("""
    MCP: \(config.enabled ? "enabled" : "disabled")
    Destructive operations: \(config.allowDestructiveOperations ? "enabled" : "disabled")
    HTTP: \(config.httpEnabled ? "enabled" : "disabled")
    HTTP endpoint: http://127.0.0.1:\(config.httpPort)/mcp
    Allowed local roots:
    \(roots.map { "  - \($0)" }.joined(separator: "\n"))
    """)
}

func printClientConfig() {
    print("""
    {
      "mcpServers": {
        "driftline": {
          "command": "driftline-mcp",
          "args": []
        }
      }
    }
    """)
}

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    let value = arguments[index + 1]
    return value.hasPrefix("--") ? nil : value
}

func portArgument(in arguments: [String]) -> Int? {
    guard let value = value(after: "--port", in: arguments), let port = Int(value), (1 ... 65535).contains(port) else {
        return nil
    }
    return port
}

func pathArgument(in arguments: [String]) -> String? {
    if let index = arguments.firstIndex(of: "--open"), arguments.indices.contains(index + 1) {
        let value = arguments[index + 1]
        return value.hasPrefix("--") ? nil : value
    }
    return arguments.first { !$0.hasPrefix("--") }
}

func bookmarkArgument(in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: "--bookmark") else { return nil }
    guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
        fputs("driftline: --bookmark requires a bookmark name\n", stderr)
        exit(2)
    }
    return arguments[index + 1]
}

func launchDriftline(argument: LaunchArgument, newTab: Bool) throws {
    let appPath = findAppBundle()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    let launchArguments = argument.appArguments + (newTab ? ["--driftline-new-tab"] : [])
    if let appPath {
        process.arguments = ["-n", appPath, "--args"] + launchArguments
    } else {
        process.arguments = ["-b", "app.driftline.Driftline", "--args"] + launchArguments
    }
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw CLIError.launchFailed
    }
}

func findAppBundle() -> String? {
    if let explicit = ProcessInfo.processInfo.environment["DRIFTLINE_APP_PATH"] {
        if FileManager.default.fileExists(atPath: explicit) {
            return explicit
        }
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var cursor: URL? = cwd
    while let current = cursor {
        let candidate = current.appendingPathComponent("dist/Driftline.app").path
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        let parent = current.deletingLastPathComponent()
        if parent.path == current.path { break }
        cursor = parent
    }
    let applications = "/Applications/Driftline.app"
    return FileManager.default.fileExists(atPath: applications) ? applications : nil
}

enum LaunchArgument {
    case path(String)
    case bookmark(String)

    var appArguments: [String] {
        switch self {
        case let .path(path):
            ["--driftline-open", path]
        case let .bookmark(name):
            ["--driftline-bookmark", name]
        }
    }

    var message: String {
        switch self {
        case let .path(path):
            "Opening Driftline at \(path)"
        case let .bookmark(name):
            "Opening Driftline bookmark \(name)"
        }
    }
}

enum CLIError: Error, LocalizedError {
    case launchFailed

    var errorDescription: String? {
        "Could not launch Driftline. Build the app bundle or install Driftline.app."
    }
}
