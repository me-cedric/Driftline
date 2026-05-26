# Testing Strategy

Driftline uses SwiftPM tests first.

## Current Tests

- Server profile duplication.
- Protocol default ports.
- Credential store test double.
- Log redaction.
- File sorting and hidden-file filtering.
- Terminal command generation without password leakage.
- JSON persistence for profiles, preferences, transfer history, and host trust records.
- Host trust unknown, trusted, and changed-fingerprint states.
- Server profile validation for required fields and port bounds.
- SFTP remote listing parser and structured SSH command generation.
- SCP upload/download command generation and result handling.
- Host fingerprint parsing, unknown-host blocking, trust flow, and changed-fingerprint blocking.
- Terminal.app AppleScript command generation.
- Driftline-managed known-hosts file writing and replacement.
- Local create/rename/delete operations.
- Remote file operation command quoting.
- Rsync progress parsing and transfer update publication.
- Transfer stats calculation.
- Credential string helper round trips.
- Bookmark and recent-server repositories.

## Planned Tests

- Keychain wrapper with safe test doubles.
- Saved server repository persistence.
- End-to-end tests against a local mocked SSH/SFTP server.
- UI tests for create folder, rename, delete, and conflict prompts.
- UI tests for credential entry and private-key picker.
- `scripts/ui-smoke.sh` app bundle launch smoke check.
- App-level UI tests for saved server create/edit/duplicate/delete flows.
- App-level UI tests for pane navigation and upload/download actions.
- Transfer queue retry/cancel/progress.
- Reconnect logic.
- UI tests for sidebar, tabs, quick connect, transfers, and inspector.

## Commands

```bash
swift test
./scripts/ui-smoke.sh
xcodebuild test -scheme Driftline
```

Use `xcodebuild` after an Xcode project or scheme is introduced.
