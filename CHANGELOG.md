# Changelog

## Unreleased

- Fixed password login on the System SSH backend: the password reaches OpenSSH through `SSH_ASKPASS` and a private FIFO, never through arguments, environment or files. Keyboard-interactive login works too.
- System SSH file operations now use the SFTP subsystem (`sftp -b`), so servers without a shell (chroot, `internal-sftp`, managed transfer servers) work.
- System SSH accepts legacy server algorithms after the OpenSSH defaults (`ssh-rsa`, DH group 14, AES-CBC) and offers only the selected private key (`IdentitiesOnly`).
- System SSH scans a host key only on first contact or on a mismatch, so OpenSSH 9.8+ `PerSourcePenalties` no longer block the Mac.
- rsync transfers fall back to SFTP when the server has no rsync; folder transfers no longer create a nested folder.
- Native Swift SFTP negotiates AES-CTR with HMAC-SHA-256 (plain and encrypt-then-MAC) for servers without AES-GCM, and explains when a server needs System SSH.
- Password profiles no longer switch the app to the experimental Native Swift SSH backend.
- Added FTP and FTPS (explicit AUTH TLS and implicit port 990) with TLS session reuse, passive mode, and a trust prompt for self-signed certificates.
- The server editor reads pasted URLs such as `sftp://user@host:2222/path`, sets the port and authentication when the protocol changes, and rejects host values that could be read as command options.
- Connection errors now show the cause instead of a generic message.
- Fixed a hang when a remote command printed more than 64 KB.
- FTPS profiles can choose explicit or implicit TLS on any port. Older profiles keep the port rule (implicit on 990).
- Cancelling one rsync transfer no longer stops the other rsync transfers.
- Renamed the app SwiftPM product to `DriftlineApp`, so the default `swift build` works on case-insensitive disks.

- Froze 1.0 scope around secure SFTP with System SSH as the default backend.
- Added 1.0 persistence and privacy/security review docs.
- Added transfer ETA display when progress, byte count, and speed are available.
- Improved compare/sync changed-file details with local/remote size and delta.
- Added corrupt JSON persistence recovery and capped transfer history storage.
- Updated release notes and Homebrew formula metadata for 0.6.0.
- Cleaned future backlog items already covered by bookmarks and conflict handling.

## 0.6.0 - 2026-06-19

- Added local MCP server integration over stdio and loopback HTTP.
- Added MCP settings, local root sandboxing, and destructive-operation gating.
- Added `driftline-mcp` executable and `driftline mcp` CLI management commands.
- Added MCP tests for tool listing, local sandboxing, profile privacy, transfer permissions, and HTTP auth.
- Automated tag-driven release packaging from CI.

## 0.5.1 - 2026-06-15

- Reworked local/remote pane splitting with a lighter custom divider and usable minimum widths.
- Fixed overlay scrollbar reveal behavior in file tables.
- Fixed stale hover highlights caused by recycled outline rows after scrolling.
- Preserved recent local/remote paths when reconnecting or switching saved profiles.
- Added reconnect affordance when a profile is selected but disconnected.
- Fixed remote parent navigation and saved-server sidebar click behavior.
- Added `~` and `~/...` handling for system SSH/SFTP command paths.
- Added native Swift SFTP `REALPATH` support for home-relative paths across browsing and transfers.
- Expanded tests around recents, path defaults, remote command quoting, and SFTP packet encoding.
- Bumped app and CLI fallback metadata to 0.5.1.

## 0.5.0 - 2026-06-15

- Refreshed macOS UI chrome, panels, inspector, transfer panel, and README screenshot.
- Added localization coverage for English, French, German, and Spanish across new app surfaces.
- Added GitHub update checks, background notifications, and a local redacted diagnostics log.
- Improved sync and transfer workflows with compare plans, local/remote winner controls, and expanded view preferences.
- Modernized CI/release tooling for macOS 15, Swift 5.10, artifact verification, and optional signing/notarization.

## 0.4.0 - 2026-06-14

- Added current-folder compare/sync preview for local-only, remote-only, and changed files.
- Improved transfer conflict handling with queued conflicts and apply-to-remaining actions.
- Added Finder-style keyboard actions for rename, info, delete, and transfer.
- Hardened native SFTP downloads with atomic local writes and safer recursive folder uploads.
- Added real-server QA tooling plus artifact verification and release manifest generation.

## 0.3.0 - 2026-06-14

- Reworked the file browser around native macOS outline views.
- Added stable Finder-like selection, double-click, sorting, expansion, context menus, and drag/drop.
- Added multi-select transfers, recursive folder transfer routing, and copy/paste transfer behavior.
- Improved transfer panel sorting and inline progress display.

## 0.2.0 - 2026-05-27

- Added native Swift SFTP password and private-key authentication with OpenSSH Ed25519 and ECDSA PEM key support.
- Added passphrase-protected OpenSSH Ed25519 key decryption via bcrypt and Blowfish.
- Added SSH agent client primitives.
- Added encrypted profile bundle export/import.
- Added recursive folder transfer support.
- Added large-file round-trip integration tests for native SFTP.
- Added Docker-based SFTP integration test harness.
- Added production-readiness audit, distribution docs, and release checklist.

## 0.1.0 - 2026-05-25

- Created Driftline naming, branding, and product direction.
- Added SwiftPM package with app, core library, CLI, and tests.
- Added SwiftUI shell: sidebar, connection toolbar, tabs, dual-pane browser, inspector, settings, and transfer panel.
- Added core domain models, Keychain abstraction, redaction, repositories, local file browser, SFTP placeholder, transfer models, and terminal command generation.
- Added open-source docs, GitHub templates, CI, release scaffolding, and security policy.
