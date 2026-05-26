# Contributing

Thanks for helping make Driftline a secure, native, open macOS transfer client.

## Workflow

1. Open an issue for user-facing behavior, protocol work, security-sensitive changes, or large UX changes.
2. Keep pull requests focused.
3. Add or update tests with behavior changes.
4. Update docs when architecture, security, UX, or release behavior changes.
5. Run `swift test` before opening a PR.

## Commit Style

Use conventional commits where possible:

- `feat: add transfer queue persistence`
- `fix: redact passphrase in connection errors`
- `docs: expand host verification model`
- `test: cover terminal command generation`

## Security

Do not include real credentials, host keys, private keys, server names, or private paths in issues, tests, screenshots, or logs.
