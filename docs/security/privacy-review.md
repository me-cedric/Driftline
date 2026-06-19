# Privacy And Security Review

Last reviewed: 2026-06-19.

## Current Decision

Driftline stays local-first for 1.0. No telemetry, crash reporting, analytics, or automatic update installer ships in 1.0.

## Network Surfaces

- SFTP/SSH: user-configured hosts only.
- Update checks: GitHub release metadata only, controlled by `checkForUpdatesOnStartup`.
- MCP: local stdio or loopback HTTP only, opt-in from Settings or CLI.
- Diagnostics: local redacted log only.

## Data Handling

- Passwords and passphrases stay in Keychain through `CredentialStore`.
- Profile JSON stores credential references, host metadata, paths, notes, and preferences only.
- Transfer history stores paths, backend/profile identity, status, timestamps, and byte counts.
- Diagnostics pass through `Redactor`; raw secrets must not be logged.
- CLI arguments must never accept passwords, passphrases, tokens, or key material.

## 1.0 Blocks

- Keep unknown hosts explicit-trust only.
- Keep changed fingerprints blocking by default.
- Keep delete and overwrite confirmation-driven unless preferences disable them.
- Document update-check behavior in release notes.
- Re-run this review before adding Sparkle, telemetry, crash reporting, or remote protocol backends.
