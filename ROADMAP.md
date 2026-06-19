# Roadmap

Driftline is pre-1.0. The roadmap favors secure SFTP workflows, native macOS polish, and release trust before adding broad protocol coverage.

## Near Term

- Finish manual accessibility pass across connection setup, host trust, file operations, transfer conflicts, settings, and keyboard workflows.
- Finish manual high-contrast and reduced-motion checks with real screenshots.
- Continue real-server QA across common OpenSSH hosts and hosted SFTP providers.
- Harden native Swift SFTP behavior against edge-case servers and network failures.
- Improve release notes and docs as the tag-driven CI flow matures.

## Before 1.0

- Configure Developer ID signing and notarization in CI.
- Document and verify signed/notarized release artifacts.
- Keep native Swift SFTP opt-in unless broader real-server QA, SSH-agent strategy, and manual accessibility/security QA are complete.
- Keep System SSH as a reliable fallback for at least one release after any backend default change.
- Privacy/security review for update checks, diagnostics, MCP, and future telemetry is recorded in `docs/security/privacy-review.md`.
- Persistence schema freeze is recorded in `docs/architecture/persistence.md`; any storage change now needs a migration test.

## Protocols And Integrations

- SSH agent-backed native Swift auth, if SwiftNIO SSH exposes the needed signer hook or Driftline adopts a safe alternative.
- WebDAV, S3, SMB, FTP, and FTPS only after protocol-specific auth, certificate, trust, and transfer semantics are designed.
- Finder extension, Shortcuts integration, Raycast extension, and menu bar transfer monitor.
- Sparkle or another automatic update mechanism after signing/notarization is in place.
- MCP SSE streaming, task support, richer audit UI, and broader real-client QA.

## Later Ideas

- Touch ID credential unlock.
- Hardware key support.
- Bandwidth rules, proxies, and jump-host UX.
- Remote editing, folder sync rules, and diff workflows.
- iCloud sync for non-secret preferences.
- Opt-in crash reporting or telemetry after privacy review.
