import DriftlineCore
import Foundation

// MARK: - ProfileTools

/// Handlers for profile/connection/trust tools.
public enum ProfileTools {
    // MARK: driftline.listProfiles

    public static func listProfiles(arguments _: JSONValue, context: MCPToolContext) async -> CallToolResult {
        do {
            let profiles = try await context.profileRepository.list()
            let items: [JSONValue] = profiles.map { self.profileJSON($0) }
            return .success(.object(["profiles": .array(items)]))
        } catch {
            return .toolError(
                code: MCPToolErrorCode.commandFailed,
                message: Redactor().redact(error.localizedDescription)
            )
        }
    }

    // MARK: driftline.getProfile

    public static func getProfile(arguments: JSONValue, context: MCPToolContext) async -> CallToolResult {
        guard let profileIdStr = arguments["profileId"]?.stringValue else {
            return .toolError(
                code: MCPToolErrorCode.invalidArguments,
                message: "profileId is required.",
                data: .object(["field": .string("profileId")])
            )
        }
        guard let profileUUID = UUID(uuidString: profileIdStr) else {
            return .toolError(
                code: MCPToolErrorCode.invalidArguments,
                message: "profileId must be a valid UUID.",
                data: .object(["field": .string("profileId")])
            )
        }

        do {
            let profileId = ServerProfileID(profileUUID)
            guard let profile = try await context.profileRepository.list().first(where: { $0.id == profileId }) else {
                return .toolError(
                    code: MCPToolErrorCode.notFound,
                    message: "No profile found with id: \(profileIdStr)",
                    data: .object(["kind": .string("profile"), "id": .string(profileIdStr)])
                )
            }
            return .success(.object(["profile": self.profileJSON(profile)]))
        } catch {
            return .toolError(
                code: MCPToolErrorCode.commandFailed,
                message: Redactor().redact(error.localizedDescription)
            )
        }
    }

    // MARK: driftline.connect

    public static func connect(arguments: JSONValue, context: MCPToolContext) async -> CallToolResult {
        guard let profileIdStr = arguments["profileId"]?.stringValue else {
            return .toolError(
                code: MCPToolErrorCode.invalidArguments,
                message: "profileId is required.",
                data: .object(["field": .string("profileId")])
            )
        }
        guard let profileUUID = UUID(uuidString: profileIdStr) else {
            return .toolError(
                code: MCPToolErrorCode.invalidArguments,
                message: "profileId must be a valid UUID.",
                data: .object(["field": .string("profileId")])
            )
        }
        let profileId = ServerProfileID(profileUUID)

        // Resolve profile.
        do {
            guard let profile = try await context.profileRepository.list().first(where: { $0.id == profileId }) else {
                return .toolError(
                    code: MCPToolErrorCode.notFound,
                    message: "No profile found with id: \(profileIdStr)",
                    data: .object(["kind": .string("profile"), "id": .string(profileIdStr)])
                )
            }

            // Standalone auth check: block Keychain-dependent auth methods.
            if context.processKind == .standalone {
                if let standaloneError = standaloneAuthError(profile: profile) {
                    return standaloneError
                }
            }

            let session = try await context.remoteFileSystem.connect(to: profile)
            await context.sessionRegistry.register(session: session, profile: profile)

            return .success(.object([
                "sessionId": .string(session.id.uuidString),
                "state": .string("connected"),
                "remotePath": .string(session.remotePath),
                "host": .string(profile.host),
                "port": .int(profile.port),
            ]))
        } catch let clientError as RemoteClientError {
            return remoteClientToolError(clientError)
        } catch {
            return .toolError(
                code: MCPToolErrorCode.connectionFailed,
                message: Redactor().redact(error.localizedDescription)
            )
        }
    }

    // MARK: driftline.disconnect

    public static func disconnect(arguments: JSONValue, context: MCPToolContext) async -> CallToolResult {
        guard let sessionId = arguments["sessionId"]?.stringValue else {
            return .toolError(
                code: MCPToolErrorCode.invalidArguments,
                message: "sessionId is required.",
                data: .object(["field": .string("sessionId")])
            )
        }
        guard let entry = await context.sessionRegistry.remove(sessionId: sessionId) else {
            return .toolError(
                code: MCPToolErrorCode.notFound,
                message: "No session found with id: \(sessionId)",
                data: .object(["kind": .string("session"), "id": .string(sessionId)])
            )
        }
        do {
            try await context.remoteFileSystem.disconnect(session: entry.session)
            return .success(.object(["disconnected": .bool(true)]))
        } catch {
            // Disconnect errors are non-fatal; still return success.
            return .success(.object(["disconnected": .bool(true)]))
        }
    }

    // MARK: driftline.trustHostInfo

    public static func trustHostInfo(arguments: JSONValue, context: MCPToolContext) async -> CallToolResult {
        guard let profileIdStr = arguments["profileId"]?.stringValue else {
            return .toolError(
                code: MCPToolErrorCode.invalidArguments,
                message: "profileId is required.",
                data: .object(["field": .string("profileId")])
            )
        }
        guard let profileUUID = UUID(uuidString: profileIdStr) else {
            return .toolError(
                code: MCPToolErrorCode.invalidArguments,
                message: "profileId must be a valid UUID.",
                data: .object(["field": .string("profileId")])
            )
        }
        let profileId = ServerProfileID(profileUUID)

        do {
            guard let profile = try await context.profileRepository.list().first(where: { $0.id == profileId }) else {
                return .toolError(
                    code: MCPToolErrorCode.notFound,
                    message: "No profile found with id: \(profileIdStr)",
                    data: .object(["kind": .string("profile"), "id": .string(profileIdStr)])
                )
            }

            // Query the trust store for this host.
            // We use a placeholder algorithm/fingerprint and check what the store says.
            // For a proper result we would need to connect to get the actual fingerprint,
            // but that would auto-negotiate — instead we report what is stored.
            let trustStatus = await resolvedTrustStatus(
                host: profile.host,
                port: profile.port,
                trustStore: context.hostTrustStore
            )

            return .success(trustStatus)
        } catch {
            return .toolError(
                code: MCPToolErrorCode.commandFailed,
                message: Redactor().redact(error.localizedDescription)
            )
        }
    }

    // MARK: - Helpers

    private static func authMethodName(_ method: AuthenticationMethod) -> String {
        switch method {
        case .password: "password"
        case .privateKey: "privateKey"
        case .agent: "agent"
        case .none: "none"
        }
    }

    private static func profileJSON(_ profile: ServerProfile) -> JSONValue {
        .object([
            "id": .string(profile.id.rawValue.uuidString),
            "displayName": .string(profile.displayName),
            "host": .string(profile.host),
            "port": .int(profile.port),
            "protocolKind": .string(profile.protocolKind.rawValue),
            "username": .string(profile.username),
            "authMethod": .string(self.authMethodName(profile.authenticationMethod)),
            "remoteDefaultPath": .string(profile.remoteDefaultPath),
            "localDefaultPath": .string(profile.localDefaultPath),
            "tags": .array(profile.tags.map { .string($0) }),
            "isFavorite": .bool(profile.isFavorite),
            "groupName": profile.groupName.map { .string($0) } ?? .null,
        ])
    }

    /// Returns a tool error if the auth method requires Keychain access unavailable in standalone mode.
    private static func standaloneAuthError(profile: ServerProfile) -> CallToolResult? {
        switch profile.authenticationMethod {
        case .password:
            .toolError(
                code: MCPToolErrorCode.authUnavailableStandalone,
                message: "Password auth is not available in the standalone server. Use key/agent auth or run the server inside Driftline.app.",
                data: .object([
                    "authMethod": .string("password"),
                    "hint": .string("Use key/agent auth or run the server inside Driftline.app."),
                ])
            )
        case let .privateKey(_, passphrase) where passphrase != nil:
            .toolError(
                code: MCPToolErrorCode.authUnavailableStandalone,
                message: "Private key with passphrase auth is not available in the standalone server. Use key/agent auth or run the server inside Driftline.app.",
                data: .object([
                    "authMethod": .string("privateKey"),
                    "hint": .string("Use key/agent auth or run the server inside Driftline.app."),
                ])
            )
        default:
            nil
        }
    }

    /// Summarise trust store state for the given host/port.
    private static func resolvedTrustStatus(
        host: String,
        port: Int,
        trustStore: any HostTrustStore
    ) async -> JSONValue {
        // We use a sentinel algorithm — actual algorithm would come from a live probe.
        // The trust store lookup with an empty fingerprint will tell us if anything is stored.
        let sentinel = "unknown"
        let result = try? await trustStore.verificationResult(
            host: host, port: port, algorithm: sentinel, fingerprint: ""
        )
        let statusString = switch result {
        case .trusted:
            "trusted"
        case .changed:
            "changed"
        case .unknown, nil:
            "unknown"
        }
        return .object([
            "host": .string(host),
            "port": .int(port),
            "algorithm": .string("(probe required for live fingerprint)"),
            "fingerprint": .string("(probe required for live fingerprint)"),
            "knownHostsLine": .string(""),
            "trustStatus": .string(statusString),
        ])
    }
}

// MARK: - RemoteClientError → CallToolResult mapping

func remoteClientToolError(_ error: RemoteClientError) -> CallToolResult {
    let redactor = Redactor()
    switch error {
    case let .hostNotTrusted(host, port, algorithm, fingerprint, knownHostsLine):
        return .toolError(
            code: MCPToolErrorCode.hostNotTrusted,
            message: "Host not trusted. Review the fingerprint before connecting.",
            data: .object([
                "host": .string(host),
                "port": .int(port),
                "algorithm": .string(algorithm),
                "fingerprint": .string(fingerprint),
                "knownHostsLine": .string(knownHostsLine),
            ])
        )
    case .hostFingerprintChanged:
        return .toolError(
            code: MCPToolErrorCode.hostFingerprintChanged,
            message: "Host fingerprint changed. Review the host before continuing.",
            data: .object([:])
        )
    case .authenticationFailed:
        return .toolError(
            code: MCPToolErrorCode.authenticationFailed,
            message: "Authentication failed. Check credentials.",
            data: .object([:])
        )
    case let .itemAlreadyExists(path):
        return .toolError(
            code: MCPToolErrorCode.itemAlreadyExists,
            message: "An item already exists at \(path).",
            data: .object(["path": .string(path)])
        )
    case let .connectionFailed(msg):
        return .toolError(
            code: MCPToolErrorCode.connectionFailed,
            message: redactor.redact(msg),
            data: .object(["detail": .string(redactor.redact(msg))])
        )
    case let .commandFailed(msg):
        return .toolError(
            code: MCPToolErrorCode.commandFailed,
            message: redactor.redact(msg),
            data: .object(["detail": .string(redactor.redact(msg))])
        )
    case let .unsupportedProtocol(kind):
        return .toolError(
            code: MCPToolErrorCode.unsupported,
            message: "Unsupported protocol: \(kind.rawValue)",
            data: .object(["detail": .string("Protocol \(kind.rawValue) is not supported.")])
        )
    case let .unsupportedAuthentication(msg):
        return .toolError(
            code: MCPToolErrorCode.unsupported,
            message: redactor.redact(msg),
            data: .object(["detail": .string(redactor.redact(msg))])
        )
    case let .nativeBackendUnavailable(msg):
        return .toolError(
            code: MCPToolErrorCode.unsupported,
            message: redactor.redact(msg),
            data: .object(["detail": .string(redactor.redact(msg))])
        )
    }
}
