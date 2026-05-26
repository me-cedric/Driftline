import Foundation

public struct ServerBookmark: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var profileID: ServerProfileID
    public var name: String
    public var localPath: String
    public var remotePath: String
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        profileID: ServerProfileID,
        name: String,
        localPath: String,
        remotePath: String,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.localPath = localPath
        self.remotePath = remotePath
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

public struct RecentServer: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var profileID: ServerProfileID
    public var displayName: String
    public var host: String
    public var protocolKind: TransferProtocolKind
    public var localPath: String
    public var remotePath: String
    public var connectedAt: Date

    public init(
        id: UUID = UUID(),
        profileID: ServerProfileID,
        displayName: String,
        host: String,
        protocolKind: TransferProtocolKind,
        localPath: String,
        remotePath: String,
        connectedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.displayName = displayName
        self.host = host
        self.protocolKind = protocolKind
        self.localPath = localPath
        self.remotePath = remotePath
        self.connectedAt = connectedAt
    }
}
