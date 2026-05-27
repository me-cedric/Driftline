# Driftline

> Native file transfer, calmly secure.

[![Swift](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://developer.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CI](https://github.com/me-cedric/Driftline/actions/workflows/ci.yml/badge.svg)](https://github.com/me-cedric/Driftline/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/me-cedric/Driftline?label=Latest%20Release)](https://github.com/me-cedric/Driftline/releases)
[![Last Commit](https://img.shields.io/github/last-commit/me-cedric/Driftline)](https://github.com/me-cedric/Driftline/commits/main)

Driftline is a modern macOS file transfer client inspired by Finder, FileZilla's practical dual-pane workflow, and polished native Mac tools. It is designed around SFTP first, with protocol adapters for FTP, FTPS, WebDAV, S3, SMB, SCP, and other backends.

![Driftline banner](assets/banner.svg)

![Driftline icon](assets/app-icon-1024.png)

## Current Status

Driftline is in early implementation. This repository contains the production architecture, SwiftUI app shell, secure domain model, Keychain abstraction, JSON persistence for non-secret app data, local and remote browsing, native Swift SFTP for password and supported private-key profiles, rsync-over-SSH transfers with SCP fallback, host trust prompts, terminal integration, CLI launch handoff, documentation, tests, and release scaffolding. System SSH remains the default stable backend; the native Swift backend is available from Settings and is covered by Docker integration tests for connect, list, remote operations, upload, download, recursive folder transfer, cancellation, and large-file round-trips.

## Features

- Native SwiftUI macOS shell with sidebar, toolbar, tabs, dual-pane browser, inspector, and transfer panel.
- First-run state is empty and user-driven; no fake example server or fake transfer queue is seeded.
- Secure server profile model with protocols, bookmarks, favorites, groups, notes, and tags.
- Saved server UI for create, edit, duplicate, and delete.
- Keychain-first credential storage abstraction; no plain-text password persistence.
- Server editor supports Keychain password/passphrase entry and private key file picking.
- Host trust record model for first-use fingerprint trust and change warnings.
- Explicit host fingerprint prompt before first SFTP connection; changed fingerprints are blocked.
- Driftline-managed `known_hosts` file with strict host checking for SSH/SCP.
- Durable JSON repositories for profiles, host trust records, transfer history, and preferences.
- Local file listing with sorting, hidden file filtering, and Finder-style metadata.
- SFTP remote listing through system SSH for SSH agent/private-key profiles.
- Native Swift SFTP backend for password auth, unencrypted OpenSSH Ed25519 keys, passphrase-protected OpenSSH Ed25519 keys, and ECDSA PEM keys.
- Native Swift SFTP upload/download for files and folders with progress and cancellation hooks.
- Upload/download execution through system `rsync` over SSH for SSH agent/private-key profiles, with live progress parsing.
- SCP transfer backend remains available as a simpler fallback implementation.
- Local and remote folder navigation with parent/refresh actions.
- Local and remote create folder, rename, and delete actions.
- Transfer conflicts support skip, overwrite, or rename before upload/download.
- Open SSH sessions in Terminal.app without exposing passwords.
- Per-tab browsing context for local/remote paths and listings.
- Bookmarks, favorites, and recent server access in the sidebar.
- Advanced view options popover for sorting, hidden files, and panel visibility.
- Transfer job and stats models for uploads, downloads, queue states, retries, cancellation, and history.
- Terminal command generation that never places passwords in CLI arguments.
- CLI scaffold: `driftline .`, `--help`, `--version`, `--open`, `--bookmark`, `--new-tab`.
- Documentation-first open-source structure with security, architecture, UX, testing, release, and roadmap docs.

## Supported Protocols

| Protocol | Status |
| --- | --- |
| SFTP | Functional through System SSH for agent/private-key workflows and through native Swift SSH/SFTP for password and unencrypted Ed25519 private-key workflows |
| FTP | Adapter planned, intentionally unsupported in code until secure behavior is implemented |
| FTPS | Adapter planned, intentionally unsupported in code until certificate and trust handling are implemented |

## Build From Source

Requirements:

- macOS 14 or newer
- Xcode 15 or newer
- Swift 5.10 or newer

```bash
git clone https://github.com/me-cedric/Driftline.git
cd Driftline
./scripts/bootstrap.sh
swift build
swift test
./scripts/ui-smoke.sh
./script/build_and_run.sh
./scripts/package-dmg.sh
```

## CLI

```bash
driftline .
driftline --open ~/Sites
driftline --bookmark staging
driftline --new-tab ~/Downloads
driftline --version
```

Driftline never accepts passwords, passphrases, tokens, or private key material as CLI arguments.

## Security First

Driftline treats credentials, host trust, logs, and terminal integration as security-sensitive surfaces.

- Credentials belong in macOS Keychain.
- Logs pass through redaction utilities.
- Host fingerprints must be explicitly trusted on first use.
- Changed host fingerprints are blocking security warnings.
- Terminal commands never embed passwords.
- Password auth is stored as a Keychain reference. System SSH execution requires agent/private-key auth to avoid unsafe password exposure; native Swift SFTP retrieves passwords from `CredentialStore` and never places them in process arguments.
- Native private-key auth supports unencrypted and passphrase-protected OpenSSH Ed25519 keys plus ECDSA PEM keys. SSH agent signing remains on the System SSH backend because SwiftNIO SSH 0.11.0 does not expose an agent-backed signer hook.
- Telemetry is absent by default. Any future telemetry must be opt-in.

Read [SECURITY.md](SECURITY.md), [docs/security/threat-model.md](docs/security/threat-model.md), and [docs/security/keychain-and-credentials.md](docs/security/keychain-and-credentials.md).

## Architecture

Driftline is package-first and split into:

- `DriftlineCore`: domain models, security, persistence protocols, protocol adapters, terminal command generation, testable utilities.
- `Driftline`: SwiftUI macOS application shell.
- `driftline`: command-line entry point.

Read [ARCHITECTURE.md](ARCHITECTURE.md) and [docs/architecture/architecture-overview.md](docs/architecture/architecture-overview.md).

## Testing

```bash
swift test
DRIFTLINE_TEST_PASSWORD='driftline-test-password' ./scripts/integration-sftp-server.sh start
DRIFTLINE_INTEGRATION_SFTP=1 DRIFTLINE_NATIVE_INTEGRATION_SFTP=1 \
  DRIFTLINE_TEST_HOST=127.0.0.1 \
  DRIFTLINE_TEST_PORT=22222 \
  DRIFTLINE_TEST_USER=driftline \
  DRIFTLINE_TEST_KEY="$PWD/.integration/ssh/id_ed25519" \
  DRIFTLINE_TEST_PASSWORD='driftline-test-password' \
  swift test
```

Current validation is SwiftPM-first. The Docker-gated SFTP tests cover System SSH, native password auth, native private-key auth, native upload/download, recursive folder transfers, cancellation, and large-file round-trips.

## Roadmap

The first milestone is a hardened SFTP MVP: complete manual accessibility/security QA, keep hardening native transfer edge cases against more real servers, and complete signed/notarized release credentials. Future ideas include Raycast, Shortcuts, Finder extension, menu bar monitor, WebDAV, S3, SMB, SCP, encrypted import/export, Touch ID unlock, and Sparkle updates.

See [ROADMAP.md](ROADMAP.md).

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=me-cedric/Driftline&type=Date)](https://star-history.com/#me-cedric/Driftline&Date)

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgements

Driftline takes inspiration from the practical transfer workflows of classic FTP/SFTP clients and the calmer interaction patterns of native macOS tools.
