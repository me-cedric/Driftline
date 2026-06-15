# CODEX.md

## Codex Operating Notes

This repository is a production-minded Swift macOS app named Driftline.

When continuing work:

1. Read `AGENTS.md`.
2. Read the root docs relevant to the task.
3. For native SFTP work, read `docs/architecture/native-swift-sftp-plan.md`.
4. Prefer small validated increments.
5. Update docs when behavior, architecture, security, release flow, or product status changes.

## Current Product State

- System SSH/SFTP remains the stable default backend.
- Native Swift SFTP is opt-in and supports password auth, unencrypted Ed25519 private-key auth, passphrase-protected Ed25519 keys, ECDSA PEM keys, host trust, connect, list, create, rename, delete, exists, file/folder upload, file/folder download, progress, cancellation, large-file tests, and home-relative path resolution.
- SSH agent auth remains on the System SSH backend because SwiftNIO SSH 0.11.0 does not expose an agent-backed user-auth signer hook.
- Docker SFTP harness is the baseline integration proof for System SSH and native Swift SFTP.
- Public release artifacts are currently unsigned/unnotarized unless signing and notarization credentials are configured.
- Tagging `v*.*.*` on a commit reachable from `main` triggers CI release packaging.

## Important Validation Note

SwiftPM occasionally leaves stale executable alias linker artifacts for this package after target changes. If a link error references `_driftline_main` or `_DriftlineApp_main`, run:

```bash
swift package clean
swift test
```
