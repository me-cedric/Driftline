# CODEX.md

## Codex Operating Notes

This repository is a production-minded Swift macOS app named Driftline.

When continuing work:

1. Read `AGENTS.md`.
2. Read `docs/implementation-log.md`.
3. For native SFTP work, read `docs/architecture/native-swift-sftp-plan.md`.
4. Prefer small validated increments.
5. Update `docs/implementation-log.md` after meaningful implementation or validation.

## Current Product State

- System SSH backend is the stable production path.
- Native Swift SFTP supports password auth, unencrypted Ed25519 private-key auth, host trust, list, create, rename, delete, exists, file upload, file download, progress, and pre-write cancellation through SwiftNIO SSH.
- Passphrase-protected keys, SSH agent auth, recursive folder transfers, and large-file stress validation are still planned.
- Docker SFTP harness is the baseline integration proof for both System SSH and native Swift password SFTP.
- Signing and notarization require external Apple credentials.

## Important Validation Note

SwiftPM occasionally leaves stale executable alias linker artifacts for this package after target changes. If a link error references `_driftline_main` or `_DriftlineApp_main`, run:

```bash
swift package clean
swift test
```
