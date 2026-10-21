import Foundation

public enum ServerProfileValidationError: Error, Equatable, LocalizedError {
    case missingDisplayName
    case missingHost
    case invalidHost
    case invalidPort
    case missingUsername
    case invalidUsername

    public var errorDescription: String? {
        switch self {
        case .missingDisplayName:
            "Enter a display name."
        case .missingHost:
            "Enter a host name or address."
        case .invalidHost:
            "Enter only the host name or address, for example sftp.example.com. Put the user name and port in their own fields."
        case .invalidPort:
            "Enter a port between 1 and 65535."
        case .missingUsername:
            "Enter a username for this authentication method."
        case .invalidUsername:
            "A username cannot start with \"-\" or contain spaces or line breaks."
        }
    }
}

public enum ServerProfileValidator {
    public static func validate(_ profile: ServerProfile) throws {
        if profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ServerProfileValidationError.missingDisplayName
        }
        if profile.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ServerProfileValidationError.missingHost
        }
        if !self.isUsableHost(profile.host) {
            throw ServerProfileValidationError.invalidHost
        }
        if !(1 ... 65535).contains(profile.port) {
            throw ServerProfileValidationError.invalidPort
        }
        if self.requiresUsername(profile.authenticationMethod), profile.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ServerProfileValidationError.missingUsername
        }
        if !profile.username.isEmpty, !self.isUsableUsername(profile.username) {
            throw ServerProfileValidationError.invalidUsername
        }
    }

    /// A host goes into ssh, sftp, curl and openssl arguments: a leading "-" would be read as an option.
    public static func isUsableHost(_ host: String) -> Bool {
        !host.hasPrefix("-")
            && !host.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }
            && !host.contains { "/\\@[]".contains($0) }
    }

    /// Usernames go into ssh, sftp and rsync arguments too. "@" stays allowed: managed servers use e-mail style users.
    public static func isUsableUsername(_ username: String) -> Bool {
        !username.hasPrefix("-")
            && !username.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }
    }

    private static func requiresUsername(_ method: AuthenticationMethod) -> Bool {
        switch method {
        case .none:
            false
        case .password, .privateKey, .agent:
            true
        }
    }
}

/// What users paste into the host field: `host`, `host:port`, `user@host`, `[2001:db8::1]:2222`,
/// or a URL such as `sftp://user@host:2222/path` (FileZilla also writes `ftpes://` for explicit FTPS).
public struct ServerAddress: Equatable, Sendable {
    public var protocolKind: TransferProtocolKind?
    public var username: String?
    public var host: String
    public var port: Int?
    public var path: String?
    /// Set for `ftps://` (implicit TLS) and `ftpes://` (explicit TLS).
    public var implicitTLS: Bool?

    public init(protocolKind: TransferProtocolKind? = nil, username: String? = nil, host: String, port: Int? = nil, path: String? = nil, implicitTLS: Bool? = nil) {
        self.protocolKind = protocolKind
        self.username = username
        self.host = host
        self.port = port
        self.path = path
        self.implicitTLS = implicitTLS
    }

    private static func scheme(_ name: String) -> (TransferProtocolKind?, Int?) {
        switch name.lowercased() {
        case "sftp", "ssh", "scp": (.sftp, nil)
        case "ftp": (.ftp, nil)
        case "ftps": (.ftps, 990)
        case "ftpes": (.ftps, 21)
        default: (nil, nil)
        }
    }

    public static func parse(_ input: String) -> ServerAddress {
        var rest = Substring(input.trimmingCharacters(in: .whitespacesAndNewlines))
        var address = ServerAddress(host: String(rest))
        if let separator = rest.range(of: "://") {
            (address.protocolKind, address.port) = self.scheme(String(rest[..<separator.lowerBound]))
            if address.protocolKind == .ftps {
                address.implicitTLS = address.port == 990
            }
            rest = rest[separator.upperBound...]
            if let slash = rest.firstIndex(of: "/") {
                let path = String(rest[slash...])
                address.path = path == "/" ? nil : path.removingPercentEncoding ?? path
                rest = rest[..<slash]
            }
        }
        if let at = rest.lastIndex(of: "@") {
            let user = String(rest[..<at])
            address.username = user.removingPercentEncoding ?? user
            rest = rest[rest.index(after: at)...]
        }
        if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            address.host = String(rest[rest.index(after: rest.startIndex) ..< close])
            let after = rest[rest.index(after: close)...]
            if after.hasPrefix(":"), let port = Int(after.dropFirst()) {
                address.port = port
            }
        } else if rest.filter({ $0 == ":" }).count == 1, let colon = rest.firstIndex(of: ":"), let port = Int(rest[rest.index(after: colon)...]) {
            address.host = String(rest[..<colon])
            address.port = port
        } else {
            address.host = String(rest)
        }
        return address
    }
}
