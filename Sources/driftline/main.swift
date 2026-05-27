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
    let path = arguments.first(where: { !$0.hasPrefix("--") }) ?? FileManager.default.currentDirectoryPath
    let resolvedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    let request = CLIRequest(localPath: resolvedPath, openInNewTab: arguments.contains("--new-tab"))
    do {
        try CLIRequestStore.save(request)
        try launchDriftline(path: resolvedPath, newTab: request.openInNewTab)
        print("Opening Driftline at \(resolvedPath)")
    } catch {
        fputs("driftline: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

func launchDriftline(path: String, newTab: Bool) throws {
    let appPath = findAppBundle()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    if let appPath {
        process.arguments = ["-n", appPath, "--args", "--driftline-open", path] + (newTab ? ["--driftline-new-tab"] : [])
    } else {
        process.arguments = ["-b", "app.driftline.Driftline", "--args", "--driftline-open", path] + (newTab ? ["--driftline-new-tab"] : [])
    }
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw CLIError.launchFailed
    }
}

func findAppBundle() -> String? {
    if let explicit = ProcessInfo.processInfo.environment["DRIFTLINE_APP_PATH"],
       FileManager.default.fileExists(atPath: explicit)
    {
        return explicit
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

enum CLIError: Error, LocalizedError {
    case launchFailed

    var errorDescription: String? {
        "Could not launch Driftline. Build the app bundle or install Driftline.app."
    }
}
