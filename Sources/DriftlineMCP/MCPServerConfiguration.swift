import DriftlineCore
import Foundation

// MARK: - MCPServerConfiguration

/// Non-secret MCP server configuration persisted to mcp.json.
/// Secrets (bearer token value) are stored only in the Keychain via tokenReference.
public struct MCPServerConfiguration: Codable, Equatable, Sendable {
    /// Master switch – server is OFF by default.
    public var enabled: Bool
    /// Gate for destructive operations (delete, overwrite). Off by default.
    public var allowDestructiveOperations: Bool
    /// Whether the local HTTP endpoint is active.
    public var httpEnabled: Bool
    /// TCP port for the HTTP endpoint (loopback only).
    public var httpPort: Int
    /// HTTP listener must bind to loopback. Kept persisted for explicit policy.
    public var bindLoopbackOnly: Bool
    /// Allowlist of local directory roots for sandbox. Empty → Downloads dir.
    public var allowedLocalRoots: [String]
    /// Keychain reference to the HTTP bearer token value.
    public var tokenReference: CredentialReference

    enum CodingKeys: String, CodingKey {
        case enabled
        case allowDestructiveOperations
        case httpEnabled
        case httpPort
        case bindLoopbackOnly
        case allowedLocalRoots
        case tokenReference
    }

    public init(
        enabled: Bool = false,
        allowDestructiveOperations: Bool = false,
        httpEnabled: Bool = false,
        httpPort: Int = 8765,
        bindLoopbackOnly: Bool = true,
        allowedLocalRoots: [String] = [],
        tokenReference: CredentialReference = CredentialReference(service: "app.driftline.mcp", account: "http-bearer")
    ) {
        self.enabled = enabled
        self.allowDestructiveOperations = allowDestructiveOperations
        self.httpEnabled = httpEnabled
        self.httpPort = httpPort
        self.bindLoopbackOnly = bindLoopbackOnly
        self.allowedLocalRoots = allowedLocalRoots
        self.tokenReference = tokenReference
    }

    /// Tolerant decoder — missing fields fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.allowDestructiveOperations = try c.decodeIfPresent(Bool.self, forKey: .allowDestructiveOperations) ?? false
        self.httpEnabled = try c.decodeIfPresent(Bool.self, forKey: .httpEnabled) ?? false
        self.httpPort = try c.decodeIfPresent(Int.self, forKey: .httpPort) ?? 8765
        self.bindLoopbackOnly = try c.decodeIfPresent(Bool.self, forKey: .bindLoopbackOnly) ?? true
        self.allowedLocalRoots = try c.decodeIfPresent([String].self, forKey: .allowedLocalRoots) ?? []
        self.tokenReference = try c.decodeIfPresent(CredentialReference.self, forKey: .tokenReference)
            ?? CredentialReference(service: "app.driftline.mcp", account: "http-bearer")
    }
}

// MARK: - MCPSettingsRepository

public protocol MCPSettingsRepository: Sendable {
    func load() async throws -> MCPServerConfiguration
    func save(_ config: MCPServerConfiguration) async throws
}

// MARK: - JSONMCPSettingsRepository

public actor JSONMCPSettingsRepository: MCPSettingsRepository {
    private let store: JSONFileStore<MCPServerConfiguration>

    public init(url: URL = DriftlineStoragePaths.mcpSettingsURL) {
        self.store = JSONFileStore(url: url)
    }

    public func load() async throws -> MCPServerConfiguration {
        try await self.store.load(default: MCPServerConfiguration())
    }

    public func save(_ config: MCPServerConfiguration) async throws {
        try await self.store.save(config)
    }
}

// MARK: - InMemoryMCPSettingsRepository

public actor InMemoryMCPSettingsRepository: MCPSettingsRepository {
    private var config: MCPServerConfiguration

    public init(config: MCPServerConfiguration = MCPServerConfiguration()) {
        self.config = config
    }

    public func load() async throws -> MCPServerConfiguration {
        self.config
    }

    public func save(_ config: MCPServerConfiguration) async throws {
        self.config = config
    }
}
