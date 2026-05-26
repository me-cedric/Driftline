import Foundation

public enum SSHCommandBuilder {
    public static func baseArguments(for profile: ServerProfile, batchMode: Bool = true, knownHostsURL: URL? = DriftlineStoragePaths.knownHostsURL) throws -> [String] {
        guard profile.protocolKind == .sftp else {
            throw RemoteClientError.unsupportedProtocol(profile.protocolKind)
        }
        if case .password = profile.authenticationMethod {
            throw RemoteClientError.unsupportedAuthentication("Password authentication is stored safely, but system SSH execution cannot use passwords without exposing them. Use SSH agent or private key authentication for this build.")
        }

        var arguments = [
            "-p", String(profile.port),
            "-o", "BatchMode=\(batchMode ? "yes" : "no")",
            "-o", "ConnectTimeout=12",
            "-o", "StrictHostKeyChecking=yes"
        ]
        if let knownHostsURL {
            arguments.append(contentsOf: ["-o", "UserKnownHostsFile=\(sshConfigEscaped(knownHostsURL.path))"])
            arguments.append(contentsOf: ["-o", "GlobalKnownHostsFile=/dev/null"])
        }
        if case .privateKey(let path, _) = profile.authenticationMethod {
            arguments.append(contentsOf: ["-i", NSString(string: path).expandingTildeInPath])
        }
        return arguments
    }

    public static func remoteListArguments(for profile: ServerProfile, path: String) throws -> [String] {
        var arguments = try baseArguments(for: profile)
        arguments.append("\(profile.username)@\(profile.host)")
        arguments.append(remoteFindCommand(path: path))
        return arguments
    }

    public static func remoteFindCommand(path: String) -> String {
        let quotedPath = shellSingleQuoted(path)
        return "LC_ALL=C find \(quotedPath) -maxdepth 1 -mindepth 1 -printf '%y\\t%s\\t%T@\\t%M\\t%u\\t%g\\t%p\\n'"
    }

    public static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func sshConfigEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: " ", with: "\\ ")
    }
}
