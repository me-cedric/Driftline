# Implementation Log

## 2026-05-25

- Completed Phase 0 naming and selected Driftline.
- Created SwiftPM package structure under `/Users/mecedric/Documents/Projects/Driftline`.
- Added app, core library, CLI, docs, templates, scripts, and tests.
- Implemented initial domain, security, persistence, local file browser, terminal command, and transfer models.
- Implemented SwiftUI app shell with sidebar, toolbar, tabs, local/remote panes, inspector, transfer panel, settings, and About placeholder.
- First `swift test` run caught a redaction bug in `Redactor`.
- Fixed redaction with explicit `NSRegularExpression` replacement and removed a Swift 6 Sendable warning from local filesystem scaffolding.
- Validation passed:
  - `swift test`: 7 tests passed.
  - `swift build`: passed.
  - `swift run driftline --help`: passed and printed CLI usage.

## 2026-05-25 Continued

- Added `JSONFileStore` for atomic Codable persistence.
- Added JSON repositories for server profiles, transfer history, view preferences, and host trust records.
- Wired `AppModel` to load profiles, preferences, and transfer history from repositories.
- Added first-run sample server seeding when no profiles exist.
- Added settings persistence on preference changes.
- Added tests for JSON profile persistence, preferences, transfer history, and host trust verification states.
- Validation passed:
  - `swift test`: 11 tests passed.
  - `swift build`: passed.

## 2026-05-25 Server Management Increment

- Added `ServerProfileValidator` with user-facing validation errors.
- Added tests for valid profiles, missing required fields, and invalid ports.
- Added saved server editor sheet for create/edit profile metadata.
- Added sidebar `New Server` action.
- Added saved server context menu actions for edit, duplicate, and delete.
- Wired profile create/edit/duplicate/delete to the JSON repository.
- Kept credential UI conservative: password profiles save only a Keychain reference; raw secret entry is deferred to the credential UI pass.
- Validation passed:
  - `swift test`: 14 tests passed.
  - `swift build`: passed.
  - `./script/build_and_run.sh --verify`: passed.

## 2026-05-25 SFTP And Transfer Increment

- Added `FoundationProcessExecutor` for structured system process execution.
- Added `SSHCommandBuilder` and `RemoteFindParser`.
- Implemented SFTP remote listing through `/usr/bin/ssh` and remote `find -printf`.
- Added password-auth guard for system SSH execution to avoid exposing secrets.
- Added SCP upload/download command builder and `SystemSCPTransferClient`.
- Wired upload/download toolbar and command-menu actions.
- Added host fingerprint lookup with `ssh-keyscan` and `ssh-keygen`.
- Added app-level first-use host trust prompt and changed-fingerprint blocking.
- Added tests for SFTP parsing/commands, SCP transfers, redacted transfer failures, host fingerprint parsing, unknown-host trust, and changed-host blocking.
- Validation passed:
  - `swift test`: 25 tests passed.
  - `swift build`: passed.
  - `./script/build_and_run.sh --verify`: passed.

## 2026-05-25 Navigation And Terminal Increment

- Added local folder navigation and default-app opening for local files.
- Added remote folder navigation using the SFTP listing adapter.
- Wired parent and refresh controls in both file browser panes.
- Added `TerminalLaunching` abstraction and Terminal.app AppleScript launcher.
- Added toolbar and command-menu action to open SSH sessions in Terminal.app.
- Added terminal launcher tests.
- Validation passed:
  - `swift test`: 26 tests passed.
  - `swift build`: passed.
  - `./script/build_and_run.sh --verify`: passed.

## 2026-05-25 File Operations And Known Hosts Increment

- Added Driftline-owned `known_hosts` path in Application Support.
- Added `ManagedKnownHostsFile` and wired host trust acceptance to write trusted host keys.
- Hardened SSH/SCP commands with `UserKnownHostsFile`, `GlobalKnownHostsFile=/dev/null`, and `StrictHostKeyChecking=yes`.
- Added local create folder, rename, delete, and exists operations.
- Added remote create folder, rename, delete, and exists command builders.
- Implemented remote create/rename/delete through structured SSH commands.
- Added UI prompts for new folder and rename.
- Added delete confirmation respecting `confirmBeforeDelete`.
- Added basic upload/download conflict refusal when destination already exists.
- Added tests for known-hosts replacement, strict SSH arguments, remote command quoting, and local file operations.
- Validation passed:
  - `swift test`: 30 tests passed.
  - `swift build`: passed.
  - `./script/build_and_run.sh --verify`: passed.

## 2026-05-25 Progress Transfer Increment

- Added `StreamingProcessExecuting` and `FoundationStreamingProcessExecutor`.
- Added `SystemRsyncTransferClient` as the default production transfer backend.
- Added `RsyncProgressParser` for live percent and speed parsing.
- Extended `TransferClient.enqueue` with an async update callback.
- Wired the app transfer queue to receive running progress updates.
- Kept `SystemSCPTransferClient` as a simpler fallback implementation.
- Added tests for rsync command generation, strict SSH transport, progress parsing, and progress update publication.
- Validation passed:
  - `swift test`: 33 tests passed.
  - `swift build`: passed.
  - `./script/build_and_run.sh --verify`: passed.

## 2026-05-25 Product Completion Pass

- Added Keychain string helper APIs.
- Added password and private-key passphrase fields to the server editor.
- Added private key file picker.
- Wired password/passphrase save into `CredentialStore`; profiles still persist only references.
- Added richer transfer conflict sheet with skip, overwrite, and rename actions.
- Added transfer panel controls for cancel active, retry failed, clear failed, and clear completed.
- Added local stats dashboard from transfer queue/history.
- Added transfer stats calculator and tests.
- Added app icon placeholder asset.
- Improved bundle metadata in the SwiftPM app wrapper.
- Made `scripts/package-dmg.sh` create `dist/Driftline.dmg` and a SHA-256 checksum.
- Validation passed:
  - `swift test`: 35 tests passed.
  - `swift build`: passed.
  - `./script/build_and_run.sh --verify`: passed.

## 2026-05-25 Original Brief Gap Closure Pass

- Added `ServerBookmark` and `RecentServer` domain models.
- Added JSON bookmark and recent-server repositories.
- Added sidebar sections for favorites, bookmarks, and recent servers.
- Added save-current connection action and favorite toggle.
- Added reconnect-last behavior using recent server state.
- Added advanced view options popover for hidden files, extensions, sorting, and panel visibility.
- Wired About popup through app commands.
- Refactored tabs to preserve per-tab session, local listing, remote listing, and selection context.
- Added status banner for actionable app messages and errors.
- Added UI smoke test script.
- Added iconset generation script for final `.icns` creation.
- Added tests for bookmark and recent-server repositories.
- Validation passed:
  - `swift test`: 37 tests passed.
  - `swift build`: passed.
  - `./scripts/ui-smoke.sh`: passed.
  - `./scripts/package-dmg.sh`: passed and created `dist/Driftline.dmg` plus checksum.

## 2026-05-25 Hardening And Distribution Pass

- Added CLI launch request persistence so `driftline .` can pass the current folder into the app without exposing secrets.
- Added app-side launch request consumption for local-folder startup and new-tab intent.
- Added active transfer cancellation plumbing through the streaming process executor and rsync backend.
- Added a gated Docker SFTP integration harness for real SSH/SFTP create, rename, delete, and host-trust checks.
- Added release workflow artifact upload and draft GitHub Release creation.
- Improved the app bundle wrapper with resource copying, optional icon inclusion, and optional signing via `DRIFTLINE_SIGN_IDENTITY`.
- Added notarization script support using `DRIFTLINE_NOTARY_PROFILE`.
- Added accessibility labels and hints across the main shell, file browsers, transfer panel, conflict prompt, and host-trust prompt.
- Removed Swift 6 concurrency warnings from the new transfer cancellation test helper.
- Validation passed:
  - `swift test`: 40 tests passed, 1 gated integration test skipped unless `DRIFTLINE_INTEGRATION_SFTP=1`.
  - `swift build`: passed.
  - `./scripts/ui-smoke.sh`: passed.
  - `./scripts/package-dmg.sh`: passed and created `dist/Driftline.dmg`.
  - `swift run driftline --help`: passed.
  - `swift run driftline --version`: passed.
- Additional validation note:
  - `./scripts/integration-sftp-server.sh start` was attempted, but Docker Desktop/daemon was not running (`docker.sock` unavailable), so the gated real SFTP integration test remains documented but unexecuted in this environment.

## 2026-05-26 Polish And Native Backend Boundary

- Removed seeded example server profiles and fake transfer jobs so first launch is user-driven.
- Changed New Connection and Quick Connect flows to open the credential/profile form instead of silently connecting to a sample server.
- Added `Save & Connect` behavior for new quick connections.
- Made saved server, favorites, bookmarks, and recent sections show clear empty states.
- Added explicit saved-server selection and context-menu connect/edit/duplicate/delete actions.
- Improved toolbar state so Connect requires a real selected server and Bookmark requires an active connection.
- Improved text contrast in file browser metadata, sidebar subtitles, transfer paths, and empty states.
- Added explanatory settings copy for the stable system SSH backend versus the guarded native Swift backend.
- Added a real empty transfer queue state.
- Added local reveal and remote path copy behavior to file-browser context menus.
- Added `swift-nio-ssh` as a pinned Swift 5.10-compatible dependency.
- Added `RemoteBackendKind`, `NativeSFTPClient`, `nativeBackendUnavailable`, and settings selection for the experimental native Swift backend.
- Added tests for native backend password credential retrieval and missing credential handling.
- Validation passed:
  - `swift test`: 42 tests passed, 1 gated integration test skipped unless `DRIFTLINE_INTEGRATION_SFTP=1`.
  - `swift build`: passed.
  - `./scripts/ui-smoke.sh`: passed.
  - `./script/build_and_run.sh --verify`: passed.
  - `./scripts/package-dmg.sh`: passed and created `dist/Driftline.dmg`.

## 2026-05-26 Productization Push

- Attempted real SFTP harness startup again; Docker daemon was still unavailable at `/Users/mecedric/.docker/run/docker.sock`, so the gated SFTP integration test remains unexecuted locally.
- Made transfer concurrency setting active in the app-level queue.
- Added per-transfer cancellation from the transfer table and kept cancel-all active transfers.
- Honored `confirmBeforeOverwrite`; conflict prompts now appear only when the preference is enabled.
- Added local default folder picker in the server editor.
- Added release readiness script at `scripts/release-check.sh`.
- Added manual QA checklist covering first launch, saved servers, SFTP flows, transfers, CLI, and packaging.
- Added release checklist covering scope freeze, validation, signing, notarization, GitHub Release, and Homebrew.
- Updated persistence and CLI request writes to avoid macOS file-protection failures in temp/test paths.
- Added a migration test for older `ViewPreferences` payloads without `remoteBackendKind`.
- Renamed placeholder asset accessibility labels to finished Driftline app icon/banner labels.
- Validation passed:
  - `swift package clean && swift test`: 43 tests passed, 1 gated integration test skipped.
  - `./scripts/release-check.sh`: passed.
  - `./scripts/release-check.sh` created `dist/Driftline.dmg` and checksum `c53531505f0c92637a100949997f5db70c1ef570741207368e0e53754c8f62f8`.
- Release readiness notes:
  - Signing was not attempted because `DRIFTLINE_SIGN_IDENTITY` is not set.
  - Notarization was not attempted because `DRIFTLINE_NOTARY_PROFILE` is not set.

## 2026-05-26 Native Swift SFTP Planning And Docker Baseline

- Started the Docker SFTP integration harness successfully on port `22222`.
- Ran the gated SFTP integration test and found two real host-trust bugs:
  - host key algorithm selection was not deterministic across trust and reconnect;
  - OpenSSH `-o UserKnownHostsFile=...` needed spaces escaped for the `Application Support` path.
- Made host fingerprint selection prefer ED25519, then ECDSA, then RSA, and match the corresponding known-hosts line.
- Escaped spaces and backslashes in `UserKnownHostsFile` paths passed through SSH config options.
- Added test coverage for escaped `UserKnownHostsFile` arguments.
- Added [native-swift-sftp-plan.md](architecture/native-swift-sftp-plan.md).
- Validation passed:
  - `swift package clean && DRIFTLINE_INTEGRATION_SFTP=1 ... swift test --filter SFTPIntegrationTests`: passed.
  - `DRIFTLINE_INTEGRATION_SFTP=1 ... swift test`: passed, 43 tests including the Docker SFTP integration test.

## 2026-05-26 Native SFTP Packet Layer Increment

- Added repo-local `AGENTS.md` and `CODEX.md` guidance.
- Added SFTP v3 packet encode/decode primitives.
- Added SFTP request builders for init, directory handles, metadata, open/read/write, remote operations, and close.
- Added SFTP attribute parsing and name entry parsing.
- Added SFTP status parsing and Driftline error mapping.
- Added native Swift authentication delegate scaffolding for SwiftNIO SSH auth offers.
- Added tests for packet framing, remaining packet bytes, incomplete packets, attrs, name parsing, and status mapping.
- Validation passed:
  - `swift test --filter SFTP`: passed, 17 focused SFTP-related tests with the Docker integration test skipped unless enabled.
  - `DRIFTLINE_INTEGRATION_SFTP=1 ... swift test`: passed, 51 tests including the Docker SFTP integration test.

## 2026-05-26 Native Swift SFTP Transport Increment

- Added direct `swift-nio` target dependencies for `NIOCore` and `NIOPosix`.
- Added `NativeSFTPHostTrustDelegate` with OpenSSH-compatible SHA-256 host-key fingerprints and known-hosts line generation.
- Added `NativeSFTPConnectionPool` and `NativeSFTPConnection` over SwiftNIO SSH.
- Added SFTP subsystem startup over a session child channel.
- Added `SSHChannelData` packet bridging and an async request/response multiplexer.
- Wired `NativeSFTPClient` password-auth profiles to real native connect, disconnect, list, create folder, rename, delete, and exists operations.
- Preserved original SSH pipeline errors so unknown hosts surface as `hostNotTrusted` instead of a generic EOF.
- Kept native private-key and SSH-agent auth guarded with explicit `nativeBackendUnavailable` messages.
- Extended the Docker SFTP harness to support optional password auth through `DRIFTLINE_TEST_PASSWORD`.
- Added a gated native Swift password SFTP integration test covering host trust, connect, create, exists, rename, list, delete, and disconnect.
- Validation passed:
  - `swift test`: passed, 52 tests with 2 gated SFTP integration tests skipped.
  - `DRIFTLINE_INTEGRATION_SFTP=1 DRIFTLINE_NATIVE_INTEGRATION_SFTP=1 ... swift test`: passed, 52 tests including System SSH and native Swift password SFTP Docker integration tests.

## 2026-05-26 Native Transfers, Private Keys, And Release Polish

- Added `Crypto` as an explicit package dependency for native SSH private-key parsing.
- Added `NativeSFTPPrivateKeyParser` for unencrypted OpenSSH Ed25519 keys and ECDSA PEM keys.
- Wired native private-key auth through SwiftNIO SSH signing for supported key formats.
- Added native SFTP file upload/download using `OPEN`, chunked `READ`, chunked `WRITE`, and `CLOSE`.
- Added `NativeSFTPTransferClient` with progress callbacks and cancellation support.
- Routed app transfers to the native transfer client when the native Swift backend is selected in Settings.
- Added Docker integration coverage for native private-key listing, native upload/download, and native upload cancellation.
- Generated `assets/app-icon-1024.png` and `assets/Driftline.icns` from the Driftline icon source artwork.
- Refreshed README status, protocol support, security notes, test commands, and roadmap language.
- Validation passed:
  - `swift package clean && DRIFTLINE_INTEGRATION_SFTP=1 DRIFTLINE_NATIVE_INTEGRATION_SFTP=1 ... swift test --filter SFTPIntegrationTests`: passed, 5 Docker SFTP integration tests.
  - `DRIFTLINE_INTEGRATION_SFTP=1 DRIFTLINE_NATIVE_INTEGRATION_SFTP=1 ... swift test`: passed, 55 tests including System SSH and native Swift SFTP Docker tests.
  - `./scripts/release-check.sh`: passed, with gated Docker tests skipped by that script unless env vars are supplied.
  - `./scripts/release-check.sh` created `dist/Driftline.dmg` and checksum `d5dd849da55e4552065e9315bf61adaa2ab0cdfe54a5831da9d75f677afabbf8`.
- Release readiness notes:
  - Signing was not attempted because `DRIFTLINE_SIGN_IDENTITY` is not set.
  - Notarization was not attempted because `DRIFTLINE_NOTARY_PROFILE` is not set.
  - Manual VoiceOver and high-contrast audit is still recommended before a tagged public release.

## 2026-05-26 Native SFTP Polish And Placeholder Audit

- Added passphrase-protected OpenSSH Ed25519 key parsing coverage with generated encrypted keys.
- Corrected the OpenSSH `bcrypt_pbkdf` output shuffling to match the OpenBSD/OpenSSH algorithm.
- Marked app-created upload/download jobs as folder transfers when the selected item is a folder.
- Added native recursive folder upload/download path normalization for macOS `/var` versus `/private/var` temporary paths.
- Added native recursive remote folder delete so non-empty directories can be removed after confirmation.
- Changed native transfer failures to update job state and rethrow, so tests and app callers can observe failures directly.
- Added a one-shot retry for transient SSH handshake closes during native connection setup.
- Renamed active branding assets away from placeholder names and updated README/scripts/docs references.
- Added `docs/product/production-readiness-audit.md` to track wired features, intentional non-production defaults, and remaining release blockers.
- Validation:
  - `swift test`: passed, 75 tests with Docker-gated integration tests skipped.
  - `DRIFTLINE_INTEGRATION_SFTP=1 DRIFTLINE_NATIVE_INTEGRATION_SFTP=1 ... swift test --filter SFTPIntegrationTests/testRecursiveFolderUploadDownloadViaSystemSFTPWhenHarnessEnabled`: passed.
  - Full `SFTPIntegrationTests` class still exposed the linuxserver.io Docker SSH daemon closing later System SSH handshakes after several native sequential tests. Individual native and system integration tests pass against a fresh harness; the full-class harness needs isolation/restart work before it can be treated as deterministic CI.

## 2026-06-19 1.0 Freeze And Small Polish

- Froze 1.0 scope around secure SFTP with System SSH as the default backend and Native Swift SFTP staying opt-in until broader QA and SSH-agent strategy are complete.
- Added persistence schema-freeze rules and a privacy/security review for update checks, diagnostics, MCP, and future telemetry.
- Added transfer ETA display when progress, byte count, and speed are available.
- Improved compare/sync changed-file details with local size, remote size, and byte delta.
- Added corrupt JSON recovery that moves bad files to `.corrupt-*` and loads defaults.
- Capped persisted transfer history at 500 jobs.
- Updated `CHANGELOG.md` with an honest 0.6.0 section, made `scripts/release-notes.sh` read the matching changelog section, and refreshed `Formula/driftline.rb` for the remote 0.6.0 source archive.
- Cleaned future backlog items already covered by bookmarks and conflict handling.
- Validation passed:
  - `swift test`: passed, 123 tests with 8 Docker-gated integration tests skipped.
  - `./scripts/lint.sh`: passed.
  - `swift package clean && ./scripts/release-check.sh`: passed and created `dist/Driftline.dmg` with checksum `e9b5756f8161b3fc1d3e0fc807af25c375f4474386e0e85c3f6877f8828c419b`.
  - `./scripts/release-notes.sh`: emitted the 0.6.0 changelog section.
  - Homebrew source archive checksum was verified by downloading `https://github.com/me-cedric/Driftline/archive/refs/tags/v0.6.0.tar.gz`.
- Release readiness notes:
  - Signing was not attempted because `DRIFTLINE_SIGN_IDENTITY` is not set.
  - Notarization was not attempted because `DRIFTLINE_NOTARY_PROFILE` is not set.
  - `brew fetch --formula ./Formula/driftline.rb` was not usable because Homebrew rejects formula files outside a tap.
