import DriftlineCore
import Foundation

let version = "0.2.0"
let arguments = Array(CommandLine.arguments.dropFirst())

func printHelp() {
    print("""
    Driftline CLI \(version)

    Usage:
      driftline [path]
      driftline --open [path]
      driftline --bookmark <name>
      driftline --new-tab [path]
      driftline --version
      driftline --help

    Notes:
      Secrets are never accepted as CLI arguments.
      The CLI records a local open request and launches Driftline.app when installed or built.
    """)
}

if arguments.contains("--help") || arguments.contains("-h") {
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
