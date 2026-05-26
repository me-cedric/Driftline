# Security Policy

## Reporting

Please do not open public issues for vulnerabilities. Email `security@example.com` or use GitHub private vulnerability reporting once enabled.

Include:

- affected version or commit
- clear reproduction steps
- security impact
- whether credentials, host trust, file deletion, or transfer integrity are involved

## Supported Versions

Driftline is pre-1.0. Security fixes target `main` until versioned releases begin.

## Security Principles

- Store secrets only in macOS Keychain.
- Never log raw passwords, passphrases, tokens, or private key material.
- Never pass passwords through CLI arguments.
- Treat host fingerprint changes as blocking security events.
- Require confirmation for destructive operations and overwrites.
- Keep telemetry off by default; future telemetry must be opt-in.
