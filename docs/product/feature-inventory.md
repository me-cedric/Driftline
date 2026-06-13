# Feature Inventory

## Implemented Scaffold

- Server profile domain model.
- Credential reference and Keychain abstraction.
- Host trust model.
- JSON persistence for server profiles, preferences, transfer history, and host trust records.
- Local file browser.
- Transfer queue domain model.
- SwiftUI app shell with sidebar, tabs, dual panes, inspector, settings, and transfer panel.
- Server profile editor for create/edit plus duplicate/delete actions.
- Keychain password/passphrase entry and private key file picker.
- Bookmarks, favorites, recent servers, and save-current connection.
- Per-tab browsing context for paths and listings.
- Advanced view options popover.
- About popup command.
- SFTP remote listing for agent/private-key profiles through system SSH.
- Rsync-over-SSH upload/download execution for agent/private-key profiles with progress parsing.
- SCP transfer backend retained as a fallback implementation.
- Host fingerprint lookup and first-use trust prompt.
- Changed host fingerprint blocking.
- Driftline-managed `known_hosts` enforcement for SSH/SCP.
- Local/remote folder navigation and parent refresh controls.
- Local/remote create folder, rename, and delete actions.
- Conflict resolver with skip, overwrite, and rename options before upload/download.
- Transfer queue controls for cancel active, retry failed, clear failed, and clear completed.
- Local stats dashboard from transfer queue/history.
- Terminal.app SSH launch.
- CLI scaffold.
- GitHub and release scaffolding.

## Planned Next

- File compare and checksum-based conflict details.
- App-level UI automation for create/edit/delete server flows, transfers, and conflicts.
- Real-server QA across SFTP-only hosts and SSH shell hosts.
- Signed and notarized public release artifacts.
- Rich estimated-time-remaining display for transfers.
