import DriftlineCore
import DriftlineMCP
import Foundation

@main
struct DriftlineMCPMain {
    static func main() async {
        do {
            let settings = JSONMCPSettingsRepository()
            let configuration = try await settings.load()
            guard configuration.enabled else {
                fputs("driftline-mcp: MCP server is disabled. Run `driftline mcp --enable` or enable it in Driftline Settings.\n", stderr)
                return
            }

            let credentialStore = KeychainCredentialStore()
            let hostTrustStore = JSONHostTrustStore()
            let ftpPins = FTPTLSPinCache()
            let context = MCPToolContext(
                localFileSystem: FoundationLocalFileSystemClient(),
                remoteFileSystem: ProtocolRoutingRemoteFileSystemClient(
                    sftp: SystemSFTPClient.secureDefault(credentialStore: credentialStore),
                    ftp: FTPClient(credentialStore: credentialStore, hostTrustStore: hostTrustStore, pinCache: ftpPins)
                ),
                transferClient: ProtocolRoutingTransferClient(
                    sftp: SystemRsyncTransferClient(credentialStore: credentialStore),
                    ftp: FTPTransferClient(credentialStore: credentialStore, hostTrustStore: hostTrustStore, pinCache: ftpPins)
                ),
                profileRepository: JSONServerProfileRepository(),
                hostTrustStore: hostTrustStore,
                sessionRegistry: MCPSessionRegistry(),
                sandbox: LocalPathSandbox(roots: configuration.allowedLocalRoots),
                configuration: configuration,
                processKind: .standalone
            )
            let transport = StdioMCPTransport(engine: MCPServer(context: context).makeEngine())
            try await transport.run()
        } catch {
            fputs("driftline-mcp: \(Redactor().redact(error.localizedDescription))\n", stderr)
            exit(1)
        }
    }
}
