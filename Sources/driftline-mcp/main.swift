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

            let context = MCPToolContext(
                localFileSystem: FoundationLocalFileSystemClient(),
                remoteFileSystem: SystemSFTPClient.secureDefault(),
                transferClient: SystemRsyncTransferClient(),
                profileRepository: JSONServerProfileRepository(),
                hostTrustStore: JSONHostTrustStore(),
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
