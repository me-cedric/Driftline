# Threat Model

## Assets

- Passwords and passphrases.
- SSH private key paths and unlock state.
- Host trust records.
- Server profile metadata.
- Local and remote file paths.
- Transfer contents.

## Threats

- Credential disclosure through files, logs, CLI args, crash reports, or screenshots.
- Man-in-the-middle attack through unverified or changed host fingerprints.
- Accidental destructive operations.
- Unsafe shell command construction.
- Dependency compromise.
- Leaky error messages.

## Controls

- Keychain-backed `CredentialStore`.
- `CredentialReference` instead of stored secrets.
- `HostTrustRecord` and changed-fingerprint blocking model.
- `Redactor` for logs.
- Structured `TerminalCommand` arguments.
- Delete and overwrite confirmations.
- GitHub dependency and code scanning workflow scaffolding.
