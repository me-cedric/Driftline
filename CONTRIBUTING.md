# Contributing

Thanks for helping make Driftline a secure, native macOS transfer client.

## Workflow

1. Open an issue for user-facing behavior, protocol work, security-sensitive changes, or large UX changes.
2. Keep pull requests focused.
3. Add or update tests for behavior changes.
4. Update docs when architecture, security, UX, release behavior, or product status changes.
5. Run validation before opening a PR:

```bash
swift test
./scripts/lint.sh
```

For app-shell work, also run:

```bash
./script/build_and_run.sh --verify
```

## Commit Style

Use conventional commits where possible:

- `feat: add transfer queue persistence`
- `fix: redact passphrase in connection errors`
- `docs: expand host verification model`
- `test: cover terminal command generation`
- `ci: automate release packaging`

## Security

Do not include real credentials, host keys, private keys, server names, private paths, or unredacted logs in issues, tests, screenshots, or docs.

Security vulnerabilities must follow [SECURITY.md](SECURITY.md), not public issues.
