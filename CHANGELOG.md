# Changelog

## 0.2.0 - 2026-05-27

- Added native Swift SFTP password and private-key authentication with OpenSSH Ed25519 and ECDSA PEM key support.
- Added passphrase-protected OpenSSH Ed25519 key decryption via bcrypt + Blowfish.
- Added SSHAgentClient for SSH agent-based authentication.
- Added EncryptedProfileExporter for secure profile bundle export/import.
- Added recursive folder transfer support (upload and download via native SFTP).
- Added large-file (50 MB) round-trip integration tests for native SFTP.
- Added upload cancellation test verifying clean close-before-write behavior.
- Added Docker-based SFTP integration test harness for password and private-key profiles.
- Added production-readiness audit, distribution docs, and release checklist.
- Updated CI with Swift 5.10 version pinning and dependency caching.
- Added CODEOWNERS and real README badges (release, last-commit, CI status).
- Fixed various test bugs and hardened native SFTP edge cases.
- Bumped GitHub Actions dependencies (checkout v6, upload-artifact v7, gh-release v3, codeql v4).

## 0.1.0 - 2026-05-25

- Created Driftline naming, branding, and product direction.
- Added SwiftPM package with app, core library, CLI, and tests.
- Added SwiftUI shell: sidebar, connection toolbar, tabs, dual-pane browser, inspector, settings, and transfer panel.
- Added core domain models, Keychain abstraction, redaction, repositories, local file browser, SFTP placeholder, transfer models, and terminal command generation.
- Added open-source docs, GitHub templates, CI, release scaffolding, and security policy.
