# Architecture

Driftline is a SwiftPM-first native macOS app with three products:

- `DriftlineCore`: UI-free domain, security, persistence, networking, transfers, terminal helpers, updates, diagnostics, and localization.
- `Driftline`: SwiftUI macOS app with narrow AppKit bridges for native outline views, menus, and desktop behavior.
- `driftline`: CLI facade for opening paths, bookmarks, and new tabs without accepting secrets.

## Core Boundaries

- `DriftlineCore` must stay UI-free and testable.
- Credentials are referenced by `CredentialReference` and resolved through `CredentialStore`.
- Saved profiles, bookmarks, recents, preferences, host trust, and transfer history live behind repository protocols.
- Remote file browsing conforms to `RemoteFileSystemClient`.
- Upload/download work conforms to `TransferClient`.
- Terminal commands are built from structured arguments or carefully quoted remote path expressions.
- SwiftUI owns app state in `Sources/DriftlineApp`; protocol clients and repositories live in core.

## Backends

| Backend | Purpose | Status |
| --- | --- | --- |
| System SSH/SFTP | Default remote browsing and transfer path using system SSH tooling. | Stable default |
| Native Swift SFTP | In-process SwiftNIO SSH/SFTP backend for password and supported key auth. | Tested, opt-in |
| SCP | Simpler transfer fallback. | Available |
| FTP/FTPS/WebDAV/S3/SMB | Future protocol adapters. | Not implemented |

## Native Swift SFTP

Native SFTP supports password auth, unencrypted and passphrase-protected Ed25519 keys, ECDSA PEM keys, host trust, list/create/rename/delete/exists, file and folder upload/download, cancellation, progress, large-file tests, and `~` remote path resolution.

SSH agent signing remains on the System SSH backend. Driftline includes native agent protocol pieces, but SwiftNIO SSH 0.11.0 does not expose the user-auth signer hook needed for agent-backed native auth.

## Release Architecture

The release workflow is tag-driven. Pushing a `v*.*.*` tag whose commit is on `main` runs lint/tests, builds the macOS app, packages `Driftline.dmg`, uploads `Driftline.dmg.sha256`, and creates the GitHub Release.

Signing and notarization are wired for manual workflow dispatch only and require Apple credentials. Do not claim public artifacts are signed or notarized unless CI or local verification proves it.

## Deep Dives

- [docs/architecture/architecture-overview.md](docs/architecture/architecture-overview.md)
- [docs/architecture/protocol-adapters.md](docs/architecture/protocol-adapters.md)
- [docs/architecture/native-swift-sftp-plan.md](docs/architecture/native-swift-sftp-plan.md)
- [docs/architecture/persistence.md](docs/architecture/persistence.md)
- [docs/architecture/dependency-decisions.md](docs/architecture/dependency-decisions.md)
