<div align="center">
<br />
<img src="assets/banner.svg" width="100%" alt="Driftline banner" />
<br /><br />
<p align="center">
<a href="#-overview">Overview</a> •
<a href="#-features">Features</a> •
<a href="#-architecture">Architecture</a> •
<a href="#-quick-start">Quick Start</a> •
<a href="#-cli">CLI</a> •
<a href="#-security">Security</a> •
<a href="#-testing">Testing</a> •
<a href="#-roadmap">Roadmap</a>
</p>
<p align="center">
<a href="https://github.com/me-cedric/Driftline/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/me-cedric/Driftline/ci.yml?branch=main&label=CI&logo=github&style=flat" alt="CI Status" /></a>
<a href="https://github.com/me-cedric/Driftline/releases/latest"><img src="https://img.shields.io/github/v/release/me-cedric/Driftline?display_name=tag&label=Release&logo=github&style=flat" alt="Latest Release" /></a>
<a href="LICENSE"><img src="https://img.shields.io/github/license/me-cedric/Driftline?label=License&style=flat" alt="MIT License" /></a>
<a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.10-orange?logo=swift&style=flat" alt="Swift 5.10" /></a>
<a href="https://developer.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&style=flat" alt="macOS 14+" /></a>
<a href="https://github.com/me-cedric/Driftline/stargazers"><img src="https://img.shields.io/github/stars/me-cedric/Driftline?style=flat&label=Stars&logo=github" alt="Stars" /></a>
<img src="https://img.shields.io/badge/platform-macOS-lightgrey?style=flat" alt="Platform" />
</p>
<br />
</div>

Driftline is a modern macOS file transfer client inspired by Finder, FileZilla's practical dual-pane workflow, and polished native Mac tools. It's designed around SFTP first, with protocol adapters for FTP, FTPS, WebDAV, S3, SMB, SCP, and other backends.

---

## 📑 Table of Contents

- [✨ Overview](#-overview)
- [🚀 Features](#-features)
  - [Secure Server Management](#secure-server-management)
  - [Dual-Pane File Browser](#dual-pane-file-browser)
  - [Transfer Engine](#transfer-engine)
  - [Native Swift SFTP](#native-swift-sftp)
  - [macOS Integration](#macos-integration)
- [🏗️ Architecture](#-architecture)
  - [Project Structure](#project-structure)
  - [Protocol Adapters](#protocol-adapters)
- [🏁 Quick Start](#-quick-start)
  - [Requirements](#requirements)
  - [Build & Run](#build--run)
- [💻 CLI](#-cli)
- [🔒 Security](#-security)
- [🧪 Testing](#-testing)
  - [Unit Tests](#unit-tests)
  - [SFTP Integration Tests](#sftp-integration-tests)
  - [Code Quality](#code-quality)
- [🗺️ Roadmap](#-roadmap)
- [⭐ Star History](#-star-history)
- [📄 License](#-license)
- [🙏 Acknowledgements](#-acknowledgements)

---

## ✨ Overview

Driftline solves a common problem for developers and sysadmins: file transfers over SSH/SFTP are typically handled by CLI tools (`scp`, `rsync`, `sftp`) or cross-platform GUI tools that feel foreign on macOS. Neither option integrates well with the Mac ecosystem.

- **Native** — Built with SwiftUI, feels like a first-class Mac app
- **Secure** — Keychain-first credential storage, host fingerprint verification, password-safe terminal integration
- **Dual backends** — System SSH for proven reliability, native Swift SFTP for password and key-based auth
- **Extensible** — Protocol adapter architecture for future backends (FTP, WebDAV, S3, etc.)

> **Status**: Active development. SFTP transfers are functional through both System SSH and native Swift backends. APIs and storage format may change before v1.0.

---

## 🚀 Features

### Secure Server Management

| Feature | Description |
|---------|-------------|
| **Keychain-first credentials** | Passwords and passphrases stored in macOS Keychain, never in plain text |
| **Host fingerprint trust** | First-use fingerprint prompt; changed fingerprints are blocked |
| **Known hosts** | Driftline-managed `known_hosts` file with strict host checking for SSH/SCP |
| **Profile model** | Protocols, bookmarks, favorites, groups, notes, tags — full CRUD |
| **Private key support** | Key file picking, passphrase entry, ECDSA PEM and Ed25519 support |

### Dual-Pane File Browser

| Feature | Description |
|---------|-------------|
| **Local browsing** | File listing with sorting, hidden file filtering, Finder-style metadata |
| **Remote browsing** | SFTP directory listing through System SSH or native Swift SFTP |
| **Folder operations** | Create, rename, delete — local and remote |
| **Per-tab state** | Independent local/remote paths and listings per tab |
| **View options** | Sort order, hidden files toggle, panel visibility popover |

### Transfer Engine

| Feature | Description |
|---------|-------------|
| **System SSH transfers** | `rsync` over SSH with live progress parsing (default backend) |
| **Native Swift SFTP** | Password and Ed25519 private-key auth, progress hooks, cancellation |
| **SCP fallback** | Simpler fallback transfer backend |
| **Recursive transfers** | Full folder upload/download with progress |
| **Conflict handling** | Skip, overwrite, or rename before transfer |
| **Transfer history** | Persistent job records with retry, cancellation, and stats |

### Native Swift SFTP

An in-process SSH/SFTP implementation built on SwiftNIO SSH:

| Capability | Status |
|------------|--------|
| Password authentication | ✅ Tested |
| Unencrypted Ed25519 keys | ✅ Tested |
| Passphrase-protected Ed25519 keys | ✅ Tested |
| ECDSA PEM keys | ✅ Tested |
| Upload/download (files & folders) | ✅ Tested |
| Cancellation | ✅ Tested |
| Large-file round-trips | ✅ Tested |
| SSH agent signing | ⏳ On System SSH only (SwiftNIO SSH 0.11.0 limitation) |

### macOS Integration

| Feature | Description |
|---------|-------------|
| **SwiftUI shell** | Sidebar, toolbar, tabs, dual-pane browser, inspector, transfer panel |
| **Terminal integration** | Open SSH sessions in Terminal.app without exposing passwords |
| **CLI launch** | `driftline .`, `--open`, `--bookmark`, `--new-tab` — zero-password CLI |
| **Bookmarks & favorites** | Quick access sidebar with recent servers |
| **Empty-first state** | No fake example servers or seeded transfer queues |

---

## 🏗️ Architecture

```
┌───────────────────────────────────────────────────────────┐
│                   Driftline (SwiftUI App)                  │
│   Features: FileBrowser │ Transfers │ Settings │ About   │
└──────────────┬────────────────────────────────────────────┘
               │
┌──────────────▼────────────────────────────────────────────┐
│                    DriftlineCore                           │
│                                                           │
│  ┌─────────────┐  ┌─────────────────────────────────┐    │
│  │ Security    │  │ Networking                       │    │
│  │ Credential  │  │ ┌─────────┐ ┌───────────────┐   │    │
│  │  Store      │  │ │ System  │ │ Native Swift  │   │    │
│  │ HostTrust   │  │ │ SSH/SFTP│ │ SFTP (NIO)    │   │    │
│  │ Encrypted   │  │ │ Rsync   │ │ SCP           │   │    │
│  │  Export     │  │ └─────────┘ └───────────────┘   │    │
│  └─────────────┘  └─────────────────────────────────┘    │
│                                                           │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │ Domain      │  │ Persistence  │  │ Terminal     │    │
│  │ Server      │  │ JSONFileStore│  │ Command Gen  │    │
│  │  Profiles   │  │ Repositories │  │ Launcher     │    │
│  │ Transfers   │  │              │  │              │    │
│  │ Connections │  │              │  │              │    │
│  └─────────────┘  └──────────────┘  └──────────────┘    │
│                                                           │
│  ┌──────────────────────────────────────────────────┐    │
│  │ Logging (Redactor)                               │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────┬────────────────────────────────────────────┘
               │
┌──────────────▼────────────────────────────────────────────┐
│                   driftline (CLI)                          │
│            Launch app, open tabs, bookmarks                │
└───────────────────────────────────────────────────────────┘
```

### Project Structure

```
Driftline/
├── Sources/
│   ├── DriftlineApp/          # SwiftUI macOS application shell
│   │   ├── App/               # App entry, content view, commands
│   │   ├── Core/              # Design system components
│   │   └── Features/          # FileBrowser, Transfers, Connections, Settings
│   ├── DriftlineCore/         # UI-free domain, security, networking
│   │   ├── Domain/            # ServerProfile, Transfer, FileItem, Connection
│   │   ├── Security/          # CredentialStore, HostTrust, EncryptedProfile
│   │   ├── Networking/        # System SSH, Native SFTP, SCP
│   │   │   └── NativeSFTP/    # SwiftNIO SSH/SFTP implementation
│   │   ├── Persistence/       # JSONFileStore, Repositories
│   │   ├── Terminal/          # Command generation, Terminal.app launch
│   │   ├── Logging/           # Redaction utilities
│   │   └── Utilities/         # StreamingProcess, CLIRequest, ViewPreferences
│   └── driftline/             # CLI entry point
├── Tests/
│   └── DriftlineCoreTests/    # Unit + integration tests (20+ test files)
├── docs/                      # Architecture, security, UX, testing docs
├── scripts/                   # Build, test, lint, release, packaging scripts
└── assets/                    # Icons, banners
```

### Protocol Adapters

| Backend | Auth Methods | Status |
|---------|-------------|--------|
| **System SSH** | SSH agent, private key | ✅ Production default; requires SSH shell utilities and rsync |
| **Native Swift SFTP** | Password, Ed25519 (plain & passphrase), ECDSA PEM | ✅ Tested, opt-in |
| **SCP** | SSH agent, private key | ✅ Fallback |
| **FTP / FTPS** | — | 🚧 Adapter planned |

---

## 🏁 Quick Start

### Requirements

- macOS 14 or newer
- Xcode 15 or newer
- Swift 5.10 or newer

### Build & Run

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

---

## 💻 CLI

```bash
driftline .
driftline --open ~/Sites
driftline --bookmark staging
driftline --new-tab ~/Downloads
driftline --version
```

Driftline never accepts passwords, passphrases, tokens, or private key material as CLI arguments.

---

## 🔒 Security

Driftline treats credentials, host trust, logs, and terminal integration as security-sensitive surfaces.

| Principle | Implementation |
|-----------|---------------|
| **No plain-text secrets** | Credentials live in macOS Keychain, never in JSON, logs, or config files |
| **Trust on first use** | Host fingerprints must be explicitly trusted before the first connection |
| **Changed fingerprints blocked** | SSH host key mismatch is a blocking security warning requiring manual review |
| **Password-safe terminal** | Terminal commands never embed passwords; System SSH uses agent/private-key auth |
| **Redacted logging** | All logs pass through `Redactor` before output |
| **Opt-in telemetry** | Absent by default; any future telemetry must be opt-in |
| **Native credential isolation** | Native Swift SFTP retrieves passwords from `CredentialStore`, never from process arguments |

Read [SECURITY.md](SECURITY.md), [docs/security/threat-model.md](docs/security/threat-model.md), and [docs/security/keychain-and-credentials.md](docs/security/keychain-and-credentials.md).

---

## 🧪 Testing

### Unit Tests

```bash
swift test
```

### SFTP Integration Tests

Requires the Docker SFTP test server:

```bash
DRIFTLINE_TEST_PASSWORD='driftline-test-password' ./scripts/integration-sftp-server.sh start

DRIFTLINE_INTEGRATION_SFTP=1 DRIFTLINE_NATIVE_INTEGRATION_SFTP=1 \
  DRIFTLINE_TEST_HOST=127.0.0.1 \
  DRIFTLINE_TEST_PORT=22222 \
  DRIFTLINE_TEST_USER=driftline \
  DRIFTLINE_TEST_KEY="$PWD/.integration/ssh/id_ed25519" \
  DRIFTLINE_TEST_PASSWORD='driftline-test-password' \
  swift test
```

Test coverage includes System SSH transfers, native password auth, native private-key auth, native upload/download, recursive folder transfers, cancellation, and large-file round-trips.

### Code Quality

```bash
./scripts/lint.sh          # SwiftLint + SwiftFormat
./scripts/release-check.sh # Release readiness validation
```

---

## 🗺️ Roadmap

**Milestone 1 — Hardened SFTP MVP** (current):
- Complete manual accessibility and security QA
- Harden native transfer edge cases against real-world servers
- Signed and notarized release credentials

**Future**:
- Raycast extension, Shortcuts integration, Finder extension
- Menu bar transfer monitor
- WebDAV, S3, SMB, SCP adapters
- Encrypted profile import/export
- Touch ID credential unlock
- Sparkle automatic updates

See [ROADMAP.md](ROADMAP.md) for details.

---

## ⭐ Star History

[![Star History Chart](https://api.star-history.com/svg?repos=me-cedric/Driftline&type=Date)](https://star-history.com/#me-cedric/Driftline&Date)

## 📄 License

MIT. See [LICENSE](LICENSE).

## 🙏 Acknowledgements

Driftline takes inspiration from the practical transfer workflows of classic FTP/SFTP clients and the calmer interaction patterns of native macOS tools.
