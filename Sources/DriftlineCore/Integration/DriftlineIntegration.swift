import Foundation

public enum DriftlineDeepLinkAction: Equatable, Sendable {
    case open
    case connect(DriftlineConnectRequest)
}

public struct DriftlineConnectRequest: Equatable, Sendable {
    public var protocolKind: TransferProtocolKind
    public var host: String
    public var port: Int
    public var username: String
    public var path: String?
    public var ignoredSecretParameters: [String]

    public init(
        protocolKind: TransferProtocolKind,
        host: String,
        port: Int,
        username: String,
        path: String? = nil,
        ignoredSecretParameters: [String] = []
    ) {
        self.protocolKind = protocolKind
        self.host = host
        self.port = port
        self.username = username
        self.path = path
        self.ignoredSecretParameters = ignoredSecretParameters
    }
}

public enum DriftlineDeepLinkError: Equatable, LocalizedError, Sendable {
    case unsupportedScheme
    case unsupportedAction
    case invalidProtocol(String?)
    case missingHost
    case invalidHost
    case invalidPort(String?)
    case missingUsername

    public var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            "Unsupported Driftline URL scheme."
        case .unsupportedAction:
            "Unsupported Driftline URL action."
        case let .invalidProtocol(value):
            "Unsupported protocol: \(value ?? "missing")."
        case .missingHost:
            "Driftline link is missing a host."
        case .invalidHost:
            "Driftline link has an invalid host."
        case let .invalidPort(value):
            "Driftline link has an invalid port: \(value ?? "missing")."
        case .missingUsername:
            "Driftline link is missing a username."
        }
    }
}

public enum DriftlineDeepLink {
    public static let scheme = "driftline"
    public static let supportedProtocols: Set<TransferProtocolKind> = [.sftp]

    private static let forbiddenSecretParameterNames: Set = [
        "auth",
        "authtoken",
        "credential",
        "key",
        "passphrase",
        "password",
        "privatekey",
        "private_key",
        "secret",
        "token",
    ]

    public static func parse(_ url: URL, supportedProtocols: Set<TransferProtocolKind> = Self.supportedProtocols) throws -> DriftlineDeepLinkAction {
        guard url.scheme?.lowercased() == self.scheme else {
            throw DriftlineDeepLinkError.unsupportedScheme
        }

        let action = Self.actionName(from: url)
        if action == "open" {
            return .open
        }

        guard action == "connect" else {
            throw DriftlineDeepLinkError.unsupportedAction
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DriftlineDeepLinkError.unsupportedAction
        }
        let queryItems = components.queryItems ?? []
        let ignoredSecretParameters = Self.ignoredSecretParameters(in: queryItems)

        let protocolValue = Self.value(named: "protocol", in: queryItems)?.lowercased()
        guard let protocolValue, let protocolKind = TransferProtocolKind(rawValue: protocolValue), supportedProtocols.contains(protocolKind) else {
            throw DriftlineDeepLinkError.invalidProtocol(protocolValue)
        }

        guard let host = Self.value(named: "host", in: queryItems)?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            throw DriftlineDeepLinkError.missingHost
        }
        guard Self.isUsableHost(host) else {
            throw DriftlineDeepLinkError.invalidHost
        }

        let portValue = Self.value(named: "port", in: queryItems)
        guard let portValue, portValue.allSatisfy(\.isNumber), let port = Int(portValue), (1 ... 65535).contains(port) else {
            throw DriftlineDeepLinkError.invalidPort(portValue)
        }

        guard let username = Self.value(named: "username", in: queryItems)?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else {
            throw DriftlineDeepLinkError.missingUsername
        }

        let path = Self.value(named: "path", in: queryItems)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .connect(DriftlineConnectRequest(
            protocolKind: protocolKind,
            host: host,
            port: port,
            username: username,
            path: path?.isEmpty == false ? path : nil,
            ignoredSecretParameters: ignoredSecretParameters
        ))
    }

    private static func actionName(from url: URL) -> String {
        if let host = url.host(percentEncoded: false), !host.isEmpty {
            return host.lowercased()
        }
        return url.pathComponents
            .first { $0 != "/" && !$0.isEmpty }?
            .lowercased() ?? ""
    }

    private static func value(named name: String, in queryItems: [URLQueryItem]) -> String? {
        queryItems.first { $0.name.lowercased() == name.lowercased() }?.value
    }

    private static func ignoredSecretParameters(in queryItems: [URLQueryItem]) -> [String] {
        let names = queryItems
            .map(\.name)
            .filter { Self.forbiddenSecretParameterNames.contains($0.lowercased()) }
        return Array(Set(names)).sorted()
    }

    private static func isUsableHost(_ host: String) -> Bool {
        if host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) {
            return false
        }
        return !host.contains("/") && !host.contains("\\") && !host.contains("@")
    }
}

public enum DriftlineIntegrationCurrentState: String, Codable, Equatable, Sendable {
    case idle
    case transferring
    case error
}

public struct DriftlineIntegrationStatusSnapshot: Codable, Equatable, Sendable {
    public var activeTransferCount: Int
    public var queuedTransferCount: Int
    public var failedTransferCount: Int
    public var currentState: DriftlineIntegrationCurrentState
    public var lastUpdatedAt: Date

    public init(
        activeTransferCount: Int = 0,
        queuedTransferCount: Int = 0,
        failedTransferCount: Int = 0,
        currentState: DriftlineIntegrationCurrentState = .idle,
        lastUpdatedAt: Date = Date()
    ) {
        self.activeTransferCount = activeTransferCount
        self.queuedTransferCount = queuedTransferCount
        self.failedTransferCount = failedTransferCount
        self.currentState = currentState
        self.lastUpdatedAt = lastUpdatedAt
    }

    public static func fromTransferStats(
        _ stats: TransferStats,
        sessionState: ConnectionState? = nil,
        lastUpdatedAt: Date = Date()
    ) -> DriftlineIntegrationStatusSnapshot {
        let currentState: DriftlineIntegrationCurrentState = if stats.activeTransfers > 0 || stats.queuedTransfers > 0 {
            .transferring
        } else if stats.failedTransfers > 0 || sessionState?.isFailure == true {
            .error
        } else {
            .idle
        }
        return DriftlineIntegrationStatusSnapshot(
            activeTransferCount: stats.activeTransfers,
            queuedTransferCount: stats.queuedTransfers,
            failedTransferCount: stats.failedTransfers,
            currentState: currentState,
            lastUpdatedAt: lastUpdatedAt
        )
    }
}

public struct DriftlineIntegrationConnectionSummary: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var protocolKind: TransferProtocolKind
    public var host: String
    public var port: Int
    public var username: String?
    public var path: String?
    public var lastUsedAt: Date?
    public var isFavorite: Bool

    public init(
        id: String,
        displayName: String,
        protocolKind: TransferProtocolKind,
        host: String,
        port: Int,
        username: String? = nil,
        path: String? = nil,
        lastUsedAt: Date? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.protocolKind = protocolKind
        self.host = host
        self.port = port
        self.username = username
        self.path = path
        self.lastUsedAt = lastUsedAt
        self.isFavorite = isFavorite
    }

    public init(profile: ServerProfile, recent: RecentServer? = nil) {
        self.init(
            id: profile.id.rawValue.uuidString,
            displayName: profile.displayName,
            protocolKind: profile.protocolKind,
            host: profile.host,
            port: profile.port,
            username: profile.username.isEmpty ? nil : profile.username,
            path: recent?.remotePath ?? profile.remoteDefaultPath,
            lastUsedAt: recent?.connectedAt,
            isFavorite: profile.isFavorite
        )
    }

    public init(recent: RecentServer, profile: ServerProfile? = nil) {
        self.init(
            id: recent.profileID.rawValue.uuidString,
            displayName: recent.displayName,
            protocolKind: recent.protocolKind,
            host: recent.host,
            port: profile?.port ?? recent.protocolKind.defaultPort,
            username: profile?.username.isEmpty == false ? profile?.username : nil,
            path: recent.remotePath,
            lastUsedAt: recent.connectedAt,
            isFavorite: profile?.isFavorite ?? false
        )
    }

    public var isValidForSnapshot: Bool {
        !self.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !self.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !self.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1 ... 65535).contains(self.port)
    }
}

public struct DriftlineIntegrationState: Codable, Equatable, Sendable {
    public var recents: [DriftlineIntegrationConnectionSummary]
    public var favorites: [DriftlineIntegrationConnectionSummary]
    public var status: DriftlineIntegrationStatusSnapshot

    public init(
        recents: [DriftlineIntegrationConnectionSummary] = [],
        favorites: [DriftlineIntegrationConnectionSummary] = [],
        status: DriftlineIntegrationStatusSnapshot = DriftlineIntegrationStatusSnapshot()
    ) {
        self.recents = recents.filter(\.isValidForSnapshot)
        self.favorites = favorites.filter(\.isValidForSnapshot)
        self.status = status
    }

    public static func sanitized(
        profiles: [ServerProfile],
        recents: [RecentServer],
        transferStats: TransferStats,
        sessionState: ConnectionState? = nil,
        lastUpdatedAt: Date = Date()
    ) -> DriftlineIntegrationState {
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let recentSummaries = recents
            .sorted { $0.connectedAt > $1.connectedAt }
            .map { recent in
                DriftlineIntegrationConnectionSummary(recent: recent, profile: profilesByID[recent.profileID])
            }
        let favoriteSummaries = profiles
            .filter(\.isFavorite)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { profile in
                DriftlineIntegrationConnectionSummary(
                    profile: profile,
                    recent: recents.first { $0.profileID == profile.id }
                )
            }
        return DriftlineIntegrationState(
            recents: recentSummaries,
            favorites: favoriteSummaries,
            status: DriftlineIntegrationStatusSnapshot.fromTransferStats(
                transferStats,
                sessionState: sessionState,
                lastUpdatedAt: lastUpdatedAt
            )
        )
    }
}

public protocol DriftlineIntegrationStateStoring: Sendable {
    func load() async throws -> DriftlineIntegrationState
    func save(_ state: DriftlineIntegrationState) async throws
}

public enum DriftlineAppGroupConfiguration {
    public static let identifierKey = "DRIFTLINE_APP_GROUP_IDENTIFIER"
    public static let snapshotFileName = "integration-snapshot.json"

    public static func identifier(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> String? {
        if let identifier = self.clean(environment[self.identifierKey]) {
            return identifier
        }
        return self.clean(bundle.object(forInfoDictionaryKey: self.identifierKey) as? String)
    }

    public static func snapshotURL(identifier: String, fileName: String = Self.snapshotFileName) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent(fileName)
    }

    public static func configuredSnapshotURL(fileName: String = Self.snapshotFileName) -> URL? {
        guard let identifier = self.identifier() else { return nil }
        return self.snapshotURL(identifier: identifier, fileName: fileName)
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}

public actor JSONDriftlineIntegrationStateStore: DriftlineIntegrationStateStoring {
    private let store: JSONFileStore<DriftlineIntegrationState>

    public init(url: URL = DriftlineAppGroupConfiguration.configuredSnapshotURL() ?? DriftlineStoragePaths.integrationSnapshotURL) {
        self.store = JSONFileStore(url: url)
    }

    public func load() async throws -> DriftlineIntegrationState {
        try await self.store.load(default: DriftlineIntegrationState())
    }

    public func save(_ state: DriftlineIntegrationState) async throws {
        try await self.store.save(state)
    }
}

public struct DriftlineWidgetSnapshotProvider: Sendable {
    private let store: (any DriftlineIntegrationStateStoring)?

    public init(store: (any DriftlineIntegrationStateStoring)? = JSONDriftlineIntegrationStateStore()) {
        self.store = store
    }

    public static func appGroup(identifier: String, fileName: String = DriftlineAppGroupConfiguration.snapshotFileName) -> DriftlineWidgetSnapshotProvider {
        guard let snapshotURL = DriftlineAppGroupConfiguration.snapshotURL(identifier: identifier, fileName: fileName) else {
            return DriftlineWidgetSnapshotProvider()
        }
        return DriftlineWidgetSnapshotProvider(
            store: JSONDriftlineIntegrationStateStore(url: snapshotURL)
        )
    }

    public func snapshot() async -> DriftlineIntegrationState {
        guard let store else { return DriftlineIntegrationState() }
        return await (try? store.load()) ?? DriftlineIntegrationState()
    }
}

private extension ConnectionState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

public struct DriftlineWidgetConnectionAction: Identifiable, Equatable, Sendable {
    public var summary: DriftlineIntegrationConnectionSummary
    public var url: URL

    public var id: String {
        self.summary.id
    }

    public init(summary: DriftlineIntegrationConnectionSummary, url: URL) {
        self.summary = summary
        self.url = url
    }
}

public enum DriftlineWidgetActionURLBuilder {
    public static let openDriftlineURL = URL(string: "driftline://open")!

    public static func connectURL(for summary: DriftlineIntegrationConnectionSummary) -> URL? {
        guard DriftlineDeepLink.supportedProtocols.contains(summary.protocolKind),
              let username = summary.username?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty,
              (1 ... 65535).contains(summary.port)
        else { return nil }

        var components = URLComponents()
        components.scheme = DriftlineDeepLink.scheme
        components.host = "connect"
        components.queryItems = [
            URLQueryItem(name: "protocol", value: summary.protocolKind.rawValue),
            URLQueryItem(name: "host", value: summary.host),
            URLQueryItem(name: "port", value: String(summary.port)),
            URLQueryItem(name: "username", value: username),
        ]
        if let path = summary.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "path", value: path))
        }

        guard let url = components.url,
              case .connect = try? DriftlineDeepLink.parse(url)
        else { return nil }
        return url
    }

    public static func connectionActions(from state: DriftlineIntegrationState, limit: Int) -> [DriftlineWidgetConnectionAction] {
        guard limit > 0 else { return [] }
        var seenIDs: Set<String> = []
        let summaries = (state.favorites + state.recents).filter { summary in
            guard !seenIDs.contains(summary.id) else { return false }
            seenIDs.insert(summary.id)
            return true
        }

        return summaries.compactMap { summary in
            guard let url = self.connectURL(for: summary) else { return nil }
            return DriftlineWidgetConnectionAction(summary: summary, url: url)
        }
        .prefix(limit)
        .map { $0 }
    }
}
