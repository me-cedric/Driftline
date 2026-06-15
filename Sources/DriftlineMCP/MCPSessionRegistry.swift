import DriftlineCore
import Foundation

// MARK: - SessionEntry

/// One live MCP session handle.
public struct MCPSessionEntry: Sendable {
    public let session: ConnectionSession
    public let profile: ServerProfile

    public init(session: ConnectionSession, profile: ServerProfile) {
        self.session = session
        self.profile = profile
    }
}

// MARK: - MCPSessionRegistry

/// Actor mapping session id strings → (ConnectionSession, ServerProfile).
/// Thread-safe; one writer per write operation.
public actor MCPSessionRegistry {
    private var sessions: [String: MCPSessionEntry] = [:]

    public init() {}

    // MARK: CRUD

    /// Register a new session. The session id is `session.id.uuidString`.
    public func register(session: ConnectionSession, profile: ServerProfile) {
        self.sessions[session.id.uuidString] = MCPSessionEntry(session: session, profile: profile)
    }

    /// Look up a session by id.  Returns nil if not found.
    public func entry(for sessionId: String) -> MCPSessionEntry? {
        self.sessions[sessionId]
    }

    /// Remove and return the entry for a session id.
    public func remove(sessionId: String) -> MCPSessionEntry? {
        self.sessions.removeValue(forKey: sessionId)
    }

    /// All currently registered session ids.
    public var allSessionIds: [String] {
        Array(self.sessions.keys)
    }
}
