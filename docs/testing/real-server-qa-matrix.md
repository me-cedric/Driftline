# Real Server QA Matrix

Use this checklist when testing Driftline against non-Docker SFTP servers. Keep hostnames and results in `docs/implementation-log.md` or a private test note. Do not commit passwords, passphrases, private keys, or production-only paths.

## Test Root

Create an empty writable remote directory before running automated tests, then point `DRIFTLINE_TEST_REMOTE_PATH` at it. The integration tests create, rename, upload, download, and delete `driftline-*` items inside this directory.

Example safe roots:

- `/home/<user>/driftline-qa`
- `/Users/<user>/driftline-qa`
- `/tmp/driftline-qa-<user>`

Do not point tests at a production directory.

## Automated Runs

System SSH / key-backed run:

```bash
DRIFTLINE_REAL_SERVER_BACKEND=system \
DRIFTLINE_TEST_HOST=example.com \
DRIFTLINE_TEST_PORT=22 \
DRIFTLINE_TEST_USER=deploy \
DRIFTLINE_TEST_KEY="$HOME/.ssh/id_ed25519" \
DRIFTLINE_TEST_REMOTE_PATH=/home/deploy/driftline-qa \
./scripts/real-server-qa.sh
```

Native Swift / password-backed run. The script prompts for `DRIFTLINE_TEST_PASSWORD` without echoing it:

```bash
DRIFTLINE_REAL_SERVER_BACKEND=native \
DRIFTLINE_TEST_HOST=example.com \
DRIFTLINE_TEST_PORT=22 \
DRIFTLINE_TEST_USER=deploy \
DRIFTLINE_TEST_REMOTE_PATH=/home/deploy/driftline-qa \
./scripts/real-server-qa.sh
```

Full run, using key tests plus native password tests:

```bash
DRIFTLINE_REAL_SERVER_BACKEND=all \
DRIFTLINE_TEST_HOST=example.com \
DRIFTLINE_TEST_PORT=22 \
DRIFTLINE_TEST_USER=deploy \
DRIFTLINE_TEST_KEY="$HOME/.ssh/id_ed25519" \
DRIFTLINE_TEST_REMOTE_PATH=/home/deploy/driftline-qa \
./scripts/real-server-qa.sh
```

## Server Matrix

| Server | Auth | Backend | Automated | Manual | Notes |
| --- | --- | --- | --- | --- | --- |
| macOS OpenSSH | SSH agent | System SSH | N/A | Browse, upload, download, Terminal | Validates agent flow in app UI |
| macOS OpenSSH | Private key | System SSH | `system` | Browse, folder transfer | Use unencrypted key for automated tests |
| macOS OpenSSH | Password | Native Swift | `native` | Browse, upload, download | Confirms password path avoids system SSH |
| Linux OpenSSH | Private key | System SSH | `system` | Large file, recursive folder | Main production-like key path |
| Linux OpenSSH | Password | Native Swift | `native` | Conflict handling, cancel/retry | Main native password path |
| Restricted/chroot SFTP | Private key or password | Matching auth | `system` or `native` | Breadcrumbs, delete/rename denial | Validates permissions/errors |

## Manual Pass

- Connect, disconnect, reconnect.
- Confirm unknown host prompt appears before first trust.
- Browse into folders with double-click.
- Select one item, then multi-select with Command-click and Shift-click.
- Expand and collapse folders with disclosure arrows.
- Sort local, remote, and transfer table columns.
- Drag selected local items to remote and remote items to local.
- Double-click a selected file to transfer it.
- Double-click a selected folder to navigate when only one folder is selected.
- Double-click while multiple files/folders are selected and confirm transfer starts.
- Use context menu actions: transfer, rename, delete, copy, paste, info.
- Use Command-C and Command-V on same-pane copy and cross-pane transfer.
- Upload and download a recursive folder.
- Trigger conflict handling and test skip, overwrite, and rename.
- Cancel queued and running transfers.
- Confirm transfer progress shows bar plus percent on one row.
- Open SSH in Terminal for key/agent profiles and confirm no password appears in command text.

## Known Gaps To Track

- Passphrase-protected private-key automated tests.
- SSH-agent automated coverage.
- Real FTP/FTPS/WebDAV/S3/SMB adapters when those backends become active.
- Accessibility QA with VoiceOver and Full Keyboard Access.
