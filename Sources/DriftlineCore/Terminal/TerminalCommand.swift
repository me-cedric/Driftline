import Foundation

public struct TerminalCommand: Equatable, Codable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public var displayString: String {
        ([executable] + arguments).map(Self.shellEscaped).joined(separator: " ")
    }

    public static func shellEscaped(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_/\-.:=@]+$"#, options: .regularExpression) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum TerminalCommandFactory {
    public static func sshCommand(for profile: ServerProfile) throws -> TerminalCommand {
        guard profile.protocolKind == .sftp else {
            throw TerminalCommandError.unsupportedProtocol(profile.protocolKind)
        }

        var args = ["-p", String(profile.port)]
        if case .privateKey(let path, _) = profile.authenticationMethod {
            args.append(contentsOf: ["-i", path])
        }
        args.append("\(profile.username)@\(profile.host)")
        return TerminalCommand(executable: "ssh", arguments: args)
    }
}

public enum TerminalCommandError: Error, Equatable {
    case unsupportedProtocol(TransferProtocolKind)
}
