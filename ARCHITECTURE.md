# Architecture

Driftline is built as a SwiftPM workspace with three products:

- `DriftlineCore`: testable domain, security, persistence, protocol, transfer, and terminal services.
- `Driftline`: native SwiftUI macOS app.
- `driftline`: CLI facade.

The app uses SwiftUI with narrow state ownership and protocol-oriented adapters. SFTP is the first real protocol target; FTP and FTPS are intentionally scaffolded until they can be implemented safely.

## Boundaries

- Domain models never know about SwiftUI.
- Credentials are referenced by `CredentialReference`, not embedded in saved server profiles.
- Persistence protocols are defined in core and can be backed by JSON, SQLite, SwiftData, or another store.
- Remote protocols conform to `RemoteFileSystemClient`.
- Transfers conform to `TransferClient`.
- Terminal commands are generated as structured arguments, not shell strings.

## Initial Tradeoff

The first SFTP adapter is a safe system-adapter placeholder. The production adapter may wrap `/usr/bin/sftp` with strict batch input/output parsing or move to SwiftNIO SSH/libssh2 after evaluation. The adapter boundary is designed so this decision does not leak into UI or domain code.
