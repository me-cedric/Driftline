# Driftline MCP Server

Driftline exposes a toggleable Model Context Protocol (MCP) surface for local AI tools. The server is off by default and adapts existing `DriftlineCore` boundaries instead of reimplementing SFTP logic.

## Products

- `DriftlineMCP`: UI-free library with JSON-RPC parsing, MCP handshake, tool routing, local path sandboxing, stdio transport, and loopback HTTP transport.
- `driftline-mcp`: standalone stdio executable for clients such as Claude Desktop and Cursor.
- `Driftline`: embedded loopback HTTP listener controlled from Settings.
- `driftline`: CLI settings facade for status, enable/disable, local roots, and client config output.

## Transports

- Stdio reads newline-delimited UTF-8 JSON-RPC messages from stdin and writes only MCP JSON messages to stdout.
- HTTP binds to `127.0.0.1` and serves one POST endpoint at `/mcp`.
- HTTP requires `Authorization: Bearer <token>`.
- HTTP rejects invalid non-local `Origin` headers to reduce DNS rebinding risk.
- SSE streaming and task-augmented execution are follow-up work.

The implementation targets MCP protocol version `2025-11-25`, with compatibility for older known revisions during initialization.

## Tools

- `driftline.listProfiles`
- `driftline.getProfile`
- `driftline.connect`
- `driftline.disconnect`
- `driftline.listDirectory`
- `driftline.stat`
- `driftline.listLocal`
- `driftline.createFolder`
- `driftline.rename`
- `driftline.upload`
- `driftline.download`
- `driftline.delete`
- `driftline.trustHostInfo`

Profile tools never emit passwords, passphrases, token values, or credential references. Connection and file tools call `RemoteFileSystemClient` and `TransferClient` implementations from `DriftlineCore`.

## Security Model

- MCP is disabled by default in `mcp.json`.
- Enabling MCP allows read operations and non-destructive writes.
- Delete and overwrite require `allowDestructiveOperations`.
- Upload, download, and local listing are restricted to `allowedLocalRoots`; empty roots default to Downloads.
- Unknown hosts and changed host fingerprints still block through existing host trust checks.
- Credentials remain behind `CredentialStore`.
- The HTTP bearer token is stored in Keychain, referenced from config, and never written to JSON.
- CLI commands never accept secrets.
- Tool errors are redacted before returning details.

## CLI

```bash
driftline mcp --status
driftline mcp --enable
driftline mcp --disable
driftline mcp --http-enable --port 8765
driftline mcp --add-root ~/Downloads
driftline mcp --print-config
```

## Client Config

```json
{
  "mcpServers": {
    "driftline": {
      "command": "driftline-mcp",
      "args": []
    }
  }
}
```

## Verification

- `swift test --filter DriftlineMCP`
- `swift build`
- `swift test`
- `./scripts/lint.sh`

Manual smoke:

```bash
printf '%s\n%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | .build/debug/driftline-mcp
```
