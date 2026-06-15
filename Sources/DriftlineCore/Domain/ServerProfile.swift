import Foundation

public enum TransferProtocolKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case sftp
    case ftp
    case ftps

    public var id: String {
        rawValue
    }

    public var defaultPort: Int {
        switch self {
        case .sftp: 22
        case .ftp: 21
        case .ftps: 990
        }
    }
}

public enum AuthenticationMethod: Hashable, Codable, Sendable {
    case password(CredentialReference)
    case privateKey(path: String, passphrase: CredentialReference?)
    case agent
    case none
}

public struct CredentialReference: Hashable, Codable, Sendable {
    public var service: String
    public var account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }
}

public struct ServerProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: ServerProfileID
    public var displayName: String
    public var host: String
    public var port: Int
    public var protocolKind: TransferProtocolKind
    public var username: String
    public var authenticationMethod: AuthenticationMethod
    public var remoteDefaultPath: String
    public var localDefaultPath: String
    public var notes: String
    public var tags: [String]
    public var isFavorite: Bool
    public var groupName: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ServerProfileID = ServerProfileID(),
        displayName: String,
        host: String,
        port: Int? = nil,
        protocolKind: TransferProtocolKind,
        username: String,
        authenticationMethod: AuthenticationMethod,
        remoteDefaultPath: String = "~",
        localDefaultPath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        notes: String = "",
        tags: [String] = [],
        isFavorite: Bool = false,
        groupName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.port = port ?? protocolKind.defaultPort
        self.protocolKind = protocolKind
        self.username = username
        self.authenticationMethod = authenticationMethod
        self.remoteDefaultPath = remoteDefaultPath
        self.localDefaultPath = localDefaultPath
        self.notes = notes
        self.tags = tags
        self.isFavorite = isFavorite
        self.groupName = groupName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func duplicated(now: Date = Date()) -> ServerProfile {
        var copy = self
        copy.id = ServerProfileID()
        copy.displayName = "\(self.displayName) Copy"
        copy.createdAt = now
        copy.updatedAt = now
        return copy
    }
}
