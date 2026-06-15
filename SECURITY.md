# Security Policy

## Reporting

Please do not open public issues for vulnerabilities.

Use GitHub private vulnerability reporting when available, or contact the maintainer privately through the contact path listed on the GitHub profile.

Include:

- affected Driftline version or commit
- clear reproduction steps
- security impact
- whether credentials, host trust, file deletion, terminal integration, or transfer integrity are involved

Do not include real passwords, passphrases, tokens, private keys, private hostnames, or unredacted logs.

## Supported Versions

Driftline is pre-1.0. Security fixes target `main` and the latest published release line.

## Security Principles

- Store secrets only in macOS Keychain.
- Never store secrets in JSON, logs, fixtures, screenshots, or docs.
- Never pass passwords or passphrases through CLI arguments or shell commands.
- Require explicit trust for unknown hosts.
- Treat host fingerprint changes as blocking events.
- Keep delete and overwrite flows confirmation-driven.
- Keep telemetry absent by default; any future telemetry must be opt-in.
- Prefer System SSH for agent-backed auth until native Swift agent signing is safely supported.

## Related Docs

- [docs/security/threat-model.md](docs/security/threat-model.md)
- [docs/security/host-verification.md](docs/security/host-verification.md)
- [docs/security/keychain-and-credentials.md](docs/security/keychain-and-credentials.md)
