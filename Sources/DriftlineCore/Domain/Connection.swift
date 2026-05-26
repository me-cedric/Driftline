import Foundation

public enum ConnectionState: Equatable, Codable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(message: String)
    case cancelling
}

public struct ConnectionSession: Identifiable, Codable, Sendable {
    public var id: UUID
    public var serverID: ServerProfileID?
    public var state: ConnectionState
    public var protocolKind: TransferProtocolKind?
    public var localPath: String
    public var remotePath: String
    public var connectedAt: Date?
    public var lastErrorMessage: String?

    public init(
        id: UUID = UUID(),
        serverID: ServerProfileID? = nil,
        state: ConnectionState = .disconnected,
        protocolKind: TransferProtocolKind? = nil,
        localPath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        remotePath: String = "/",
        connectedAt: Date? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.serverID = serverID
        self.state = state
        self.protocolKind = protocolKind
        self.localPath = localPath
        self.remotePath = remotePath
        self.connectedAt = connectedAt
        self.lastErrorMessage = lastErrorMessage
    }
}
