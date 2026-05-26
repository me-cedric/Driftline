# Manual QA Checklist

Use this checklist before tagging a release. Record results in `docs/implementation-log.md`.

## Local App

- Launch `./script/build_and_run.sh`.
- Confirm first launch has no fake saved server and no fake transfer rows.
- Create a new connection and confirm the sheet asks for display name, host, protocol, username, authentication method, credentials, and paths.
- Use the local folder picker and private-key picker.
- Save a server, edit it, duplicate it, favorite it, delete the duplicate.
- Confirm saved server, favorites, bookmarks, and recent sections update correctly.
- Toggle inspector, sidebar, transfer queue, hidden files, and sort settings.
- Confirm readable text in light mode and dark mode.

## SFTP With Real Server

- Connect with SSH agent auth.
- Connect with private-key auth.
- Confirm unknown host fingerprint prompt appears before first connection.
- Trust the host and confirm a Driftline-owned `known_hosts` entry is written.
- Browse remote folders.
- Create, rename, and delete a remote folder.
- Upload a local file.
- Download a remote file.
- Trigger a file conflict and test skip, overwrite, and rename.
- Disconnect and reconnect.
- Open SSH in Terminal and confirm no password appears in the command.

## Transfers

- Set transfer concurrency to `1` and start multiple transfers; confirm only one runs at a time.
- Cancel a queued transfer.
- Cancel a running transfer.
- Retry a failed transfer.
- Clear completed transfers.
- Clear failed transfers.
- Confirm transfer history persists after restart without showing fake seed data.

## CLI

- Run `swift run driftline --help`.
- Run `swift run driftline --version`.
- Run `swift run driftline .` and confirm the app opens on the current local folder.
- Confirm CLI arguments never accept passwords or passphrases.

## Packaging

- Run `./scripts/release-check.sh`.
- Install from `dist/Driftline.dmg` on a clean macOS account.
- If signing credentials are available, verify `codesign --verify --deep --strict --verbose=2 dist/Driftline.app`.
- If notarization credentials are available, run `DRIFTLINE_NOTARY_PROFILE=... ./scripts/notarize.sh`.
