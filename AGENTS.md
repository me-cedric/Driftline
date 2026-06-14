# AGENTS.md

## Project Guidance

Driftline is a SwiftPM-first native macOS app. Treat this file as repo-local guidance for AI coding agents working in this repository.

## Commands

- Build: `swift build`
- Test: `swift test`
- Clean flaky SwiftPM executable alias artifacts: `swift package clean`
- Run app bundle: `./script/build_and_run.sh`
- Verify app bundle launches: `./script/build_and_run.sh --verify`
- UI smoke test: `./scripts/ui-smoke.sh`
- Lint/format check: `./scripts/lint.sh`
- Package DMG: `./scripts/package-dmg.sh`
- Release readiness: `./scripts/release-check.sh`
- Start SFTP integration server: `./scripts/integration-sftp-server.sh start`
- Run SFTP integration tests:
  ```bash
  DRIFTLINE_INTEGRATION_SFTP=1 \
  DRIFTLINE_TEST_HOST=127.0.0.1 \
  DRIFTLINE_TEST_PORT=22222 \
  DRIFTLINE_TEST_USER=driftline \
  DRIFTLINE_TEST_KEY=/Users/mecedric/Documents/Projects/Driftline/.integration/ssh/id_ed25519 \
  swift test
  ```
- Run native Swift password SFTP integration tests:
  ```bash
  DRIFTLINE_TEST_PASSWORD='driftline-test-password' ./scripts/integration-sftp-server.sh start
  DRIFTLINE_INTEGRATION_SFTP=1 \
  DRIFTLINE_NATIVE_INTEGRATION_SFTP=1 \
  DRIFTLINE_TEST_HOST=127.0.0.1 \
  DRIFTLINE_TEST_PORT=22222 \
  DRIFTLINE_TEST_USER=driftline \
  DRIFTLINE_TEST_KEY=/Users/mecedric/Documents/Projects/Driftline/.integration/ssh/id_ed25519 \
  DRIFTLINE_TEST_PASSWORD='driftline-test-password' \
  swift test
  ```

## Architecture Rules

- Keep `DriftlineCore` UI-free and testable.
- Always run `./scripts/lint.sh` during final verification for code changes; CI treats lint/format drift as a failure.
- Keep SwiftUI app state in `Sources/DriftlineApp`.
- Do not store secrets in JSON, logs, command arguments, docs, or fixtures.
- Credentials belong behind `CredentialStore`.
- Non-sensitive app data belongs behind repository protocols.
- SFTP/SSH work must preserve the `RemoteFileSystemClient` and `TransferClient` boundaries.
- Native Swift SFTP work must follow `docs/architecture/native-swift-sftp-plan.md`.
- Native Swift SFTP currently has Docker coverage for password auth, unencrypted Ed25519 private-key auth, connect, list, create, rename, delete, upload, download, and pre-write cancel.
- Do not mark native Swift SFTP production-ready until large-file transfer tests, recursive folder transfers, passphrase-protected keys, and a manual accessibility/security QA pass are complete.

## Security Rules

- Never pass passwords or passphrases to shell commands.
- Never log secrets or raw command stderr without redaction.
- Host fingerprint changes must block by default.
- Unknown hosts must require explicit trust.
- Delete and overwrite flows must remain confirmation-driven unless preferences explicitly disable confirmation.

## Git Rules

- Use conventional commits when committing.
- Do not commit `.build/`, `dist/`, `.integration/`, `.xcresult`, or generated local artifacts.
- Do not revert user changes without explicit instruction.
