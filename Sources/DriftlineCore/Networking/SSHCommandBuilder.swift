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
    /// Older servers only offer these algorithms. They are appended after the OpenSSH defaults, so a modern server still negotiates the strongest shared choice.
    public static let legacyCompatibilityOptions = [
        "HostKeyAlgorithms=+ssh-rsa",
        "PubkeyAcceptedAlgorithms=+ssh-rsa",
        "KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1",
        "Ciphers=+aes128-cbc,aes256-cbc",
    ]

    public static func baseArguments(for profile: ServerProfile, batchMode: Bool = true, knownHostsURL: URL? = DriftlineStoragePaths.knownHostsURL, jumpHosts: [JumpHost] = []) throws -> [String] {
        guard profile.protocolKind == .sftp else {
            throw RemoteClientError.unsupportedProtocol(profile.protocolKind)
        }
        // Profiles from older versions or other tools skip the editor validation; ssh would read "-..." as an option.
        guard ServerProfileValidator.isUsableHost(profile.host), ServerProfileValidator.isUsableUsername(profile.username) else {
            throw RemoteClientError.unsupportedAuthentication("The host or username of this server is not valid. Edit the server.")
        }

        // Secrets reach ssh only through SSH_ASKPASS (see SSHAskPassSession), so prompts must stay enabled for them.
        let usesSecretPrompt = self.usesSecretPrompt(profile.authenticationMethod)
        var arguments = [
            "-p", String(profile.port),
            "-o", "BatchMode=\(batchMode && !usesSecretPrompt ? "yes" : "no")",
            "-o", "ConnectTimeout=12",
            "-o", "ServerAliveInterval=15",
            "-o", "StrictHostKeyChecking=yes",
        ]
        for option in self.legacyCompatibilityOptions {
            arguments.append(contentsOf: ["-o", option])
        }
        if let knownHostsURL {
            arguments.append(contentsOf: ["-o", "UserKnownHostsFile=\(self.sshConfigEscaped(knownHostsURL.path))"])
            arguments.append(contentsOf: ["-o", "GlobalKnownHostsFile=/dev/null"])
        }
        switch profile.authenticationMethod {
        case .password:
            arguments.append(contentsOf: [
                "-o", "PreferredAuthentications=password,keyboard-interactive",
                "-o", "PubkeyAuthentication=no",
                "-o", "NumberOfPasswordPrompts=1",
            ])
        case let .privateKey(path, _):
            // IdentitiesOnly stops agent keys from using up the server's MaxAuthTries before this key is offered.
            arguments.append(contentsOf: ["-i", NSString(string: path).expandingTildeInPath, "-o", "IdentitiesOnly=yes"])
        case .agent, .none:
            break
        }
        if !jumpHosts.isEmpty {
            arguments.append(contentsOf: ["-o", "ProxyJump=\(self.jumpProxyValue(for: jumpHosts))"])
        }
        return arguments
    }

    /// Arguments for `sftp -b -`. The ssh options come before `-b`, because `-b` adds `BatchMode=yes` and ssh keeps the first value of an option.
    public static func sftpBatchArguments(for profile: ServerProfile, batchFile: String = "-", knownHostsURL: URL? = DriftlineStoragePaths.knownHostsURL) throws -> [String] {
        var arguments = try self.baseArguments(for: profile, knownHostsURL: knownHostsURL)
        arguments[0] = "-P" // sftp uses -P for the port.
        arguments.append(contentsOf: ["-b", batchFile, "\(profile.username)@\(profile.host)"])
        return arguments
    }

    static func usesSecretPrompt(_ method: AuthenticationMethod) -> Bool {
        switch method {
        case .password:
            true
        case let .privateKey(_, passphrase):
            passphrase != nil
        case .agent, .none:
            false
        }
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
