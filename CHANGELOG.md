# Changelog

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
