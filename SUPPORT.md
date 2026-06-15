# Support

Use GitHub Issues for bugs, feature requests, protocol requests, documentation fixes, and UX feedback.

Security vulnerabilities must follow [SECURITY.md](SECURITY.md), not public issues.

## Good Bug Reports

Include:

- macOS version
- Driftline version or commit SHA
- backend: System SSH, Native Swift SFTP, SCP, or local-only
- protocol/auth method involved
- whether the issue affects local browsing, remote browsing, transfers, terminal integration, credentials, updates, or release artifacts
- expected behavior
- actual behavior
- redacted logs or screenshots only

## Useful Commands

```bash
swift test
./scripts/lint.sh
./script/build_and_run.sh --verify
```
