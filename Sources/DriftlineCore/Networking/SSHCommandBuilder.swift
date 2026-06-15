import Foundation

public struct JumpHost: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var username: String?

    public init(host: String, port: Int = 22, username: String? = nil) {
        self.host = host
        self.port = port
        self.username = username
    }
}

public enum SSHCommandBuilder {
    public static func baseArguments(for profile: ServerProfile, batchMode: Bool = true, knownHostsURL: URL? = DriftlineStoragePaths.knownHostsURL, jumpHosts: [JumpHost] = []) throws -> [String] {
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
            "-o", "StrictHostKeyChecking=yes",
        ]
        if let knownHostsURL {
            arguments.append(contentsOf: ["-o", "UserKnownHostsFile=\(self.sshConfigEscaped(knownHostsURL.path))"])
            arguments.append(contentsOf: ["-o", "GlobalKnownHostsFile=/dev/null"])
        }
        if case let .privateKey(path, _) = profile.authenticationMethod {
            arguments.append(contentsOf: ["-i", NSString(string: path).expandingTildeInPath])
        }
        if !jumpHosts.isEmpty {
            arguments.append(contentsOf: ["-o", "ProxyJump=\(self.jumpProxyValue(for: jumpHosts))"])
        }
        return arguments
    }

    public static func jumpProxyValue(for jumpHosts: [JumpHost]) -> String {
        jumpHosts.map { jump in
            let hostPort = "\(jump.host):\(jump.port)"
            if let username = jump.username {
                return "\(username)@\(hostPort)"
            }
            return hostPort
        }.joined(separator: ",")
    }

    public static func remoteListArguments(for profile: ServerProfile, path: String) throws -> [String] {
        var arguments = try baseArguments(for: profile)
        arguments.append("\(profile.username)@\(profile.host)")
        arguments.append(self.remoteFindCommand(path: path))
        return arguments
    }

    public static func remoteFindCommand(path: String) -> String {
        let quotedPath = self.remoteShellPathExpression(path)
        return "LC_ALL=C find \(quotedPath) -maxdepth 1 -mindepth 1 -printf '%y\\t%s\\t%T@\\t%M\\t%u\\t%g\\t%p\\n'"
    }

    public static func remoteShellPathExpression(_ path: String) -> String {
        if path == "~" {
            return "\"$HOME\""
        }
        if path.hasPrefix("~/") {
            let suffix = String(path.dropFirst(2))
            return suffix.isEmpty ? "\"$HOME\"" : "\"$HOME\"/\(self.shellSingleQuoted(suffix))"
        }
        return self.shellSingleQuoted(path)
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
