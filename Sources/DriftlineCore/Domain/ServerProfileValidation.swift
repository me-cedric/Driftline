import Foundation

public enum ServerProfileValidationError: Error, Equatable, LocalizedError {
    case missingDisplayName
    case missingHost
    case invalidPort
    case missingUsername

    public var errorDescription: String? {
        switch self {
        case .missingDisplayName:
            "Enter a display name."
        case .missingHost:
            "Enter a host name or address."
        case .invalidPort:
            "Enter a port between 1 and 65535."
        case .missingUsername:
            "Enter a username for this authentication method."
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
        if !(1...65_535).contains(profile.port) {
            throw ServerProfileValidationError.invalidPort
        }
        if requiresUsername(profile.authenticationMethod), profile.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ServerProfileValidationError.missingUsername
        }
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
