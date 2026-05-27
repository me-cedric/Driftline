import Foundation

public struct ServerProfileID: Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID
    public var id: UUID {
        self.rawValue
    }

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct TransferJobID: Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID
    public var id: UUID {
        self.rawValue
    }

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
