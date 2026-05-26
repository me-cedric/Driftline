# Native Swift SFTP Plan

This plan replaces the guarded `NativeSFTPClient` placeholder with a production Swift implementation built on Apple SwiftNIO SSH.

## Goals

- Support SFTP without shelling out to `ssh`, `find`, `scp`, or `rsync`.
- Support password authentication without exposing secrets in process arguments.
- Support private-key authentication and passphrase retrieval from Keychain.
- Keep host trust explicit, auditable, and compatible with Driftline's existing trust UI.
- Provide structured cancellation, progress, and typed user-facing errors.
- Preserve the existing `RemoteFileSystemClient` and `TransferClient` contracts so UI code does not need a large rewrite.

## Non-Goals For The First Native Milestone

- FTP/FTPS.
- SSH agent support, unless it is small after password and private-key auth are working.
- Resume-after-restart transfer recovery.
- SFTP protocol versions beyond v3 unless negotiated safely.
- Remote file editing, diff, sync, or checksums.

## Current Baseline

- System SSH backend is functional for private-key/agent SFTP flows.
- Docker SFTP integration harness is available.
- `NativeSFTPClient` currently retrieves credentials and then returns `nativeBackendUnavailable`.
- `swift-nio-ssh` is pinned in `Package.swift`.

## Implementation Status

Implemented:

- Repo guidance: `AGENTS.md` and `CODEX.md`.
- SFTP v3 packet framing with decode/encode tests.
- SFTP request builders for init, directory, metadata, file operations, and transfer primitives.
- SFTP attributes parser for size, uid/gid, permissions, access time, modified time, and extensions.
- SFTP name parser for `SSH_FXP_NAME` payloads.
- SFTP status parser and mapping into Driftline remote errors.
- Native Swift auth delegate scaffolding for password, private key, and none offers.
- Docker SFTP baseline validation for the existing system backend.
- Live SwiftNIO TCP connection lifecycle for password-auth profiles.
- Secure `NIOSSHClientServerAuthenticationDelegate` fingerprint conversion from `NIOSSHPublicKey` into Driftline trust records.
- Session child channel SFTP subsystem startup.
- `SSHChannelData`/`ByteBuffer` bridge for SFTP packets.
- Async request/response multiplexer over the child channel.
- Native directory listing and basic remote file operations:
  - list
  - create folder
  - rename
  - delete file/folder
  - exists check
- Docker SFTP password-auth validation for the native Swift backend.
- Native private-key parsing/signing for:
  - unencrypted OpenSSH Ed25519 keys;
  - ECDSA P-256/P-384/P-521 PEM keys.
- Native upload/download transfer engine for files.
- Progress reporting with bytes-per-second estimates.
- Cancellation checks that close native channels and handles.

Not implemented yet:

- Native SSH agent auth.
- Passphrase-protected OpenSSH private keys.
- Native folder-recursive upload/download.
- Rich estimated-time-remaining display.
- Persistent native connection reuse across app launches.

## SwiftNIO SSH Shape

From SwiftNIO SSH docs and local package APIs:

- Configure the client with `SSHClientConfiguration`.
- Provide a `ClientUserAuthenticationDelegate` for password/private-key auth.
- Provide a `NIOSSHClientServerAuthenticationDelegate` for host-key validation.
- Connect over `ClientBootstrap` and install `NIOSSHHandler`.
- Retrieve `NIOSSHHandler` from the pipeline and open a `.session` child channel with `createChannel`.
- Request SFTP with `SSHChannelRequestEvent.SubsystemRequest(subsystem: "sftp", wantReply: true)`.
- Bridge `SSHChannelData` to `ByteBuffer` for SFTP packet reads/writes.

## Proposed Modules

```text
Sources/DriftlineCore/Networking/NativeSFTP/
  NativeSFTPClient.swift
  NativeSFTPConnection.swift
  NativeSFTPConnectionPool.swift
  NIOSSHPasswordAuthDelegate.swift
  NIOSSHPrivateKeyAuthDelegate.swift
  NIOSSHHostTrustDelegate.swift
  SFTPChannel.swift
  SFTPPacket.swift
  SFTPOperation.swift
  SFTPAttributes.swift
  SFTPErrorMapper.swift
  SFTPTransferClient.swift
```

Keep `Sources/DriftlineCore/Networking/NativeSFTPClient.swift` as the public facade during migration, then move internals under the folder above.

## Milestone 1: Transport And Authentication

Expected behavior:

- `NativeSFTPClient.connect(to:)` opens a TCP connection to `host:port`.
- Password auth reads the password from `CredentialStore`.
- Private-key auth reads a passphrase from `CredentialStore` when configured.
- Host-key validation checks `HostTrustStore`.
- Unknown host throws `hostNotTrusted` with enough data for the existing trust prompt.
- Changed host throws `hostFingerprintChanged`.
- Cancellation closes the underlying channel and event loop resources.

Implementation tasks:

- Add `NativeSFTPConnection` actor wrapping `Channel`, `EventLoopGroup`, session child channel, and the SFTP channel handler.
- Add `NativeSFTPHostTrustDelegate` that computes a SHA-256 fingerprint from `NIOSSHPublicKey`.
- Add auth delegate support:
  - `NativeSFTPAuthDelegate` for password auth.
  - Private-key auth offer scaffolding exists, but file parsing/signing is not enabled yet.
- Add integration test using the Docker server for host trust and password auth when the harness enables password mode.
- Add private-key integration test using the existing harness key.

Exit criteria:

- Connect succeeds against Docker SFTP with password auth.
- Password profile fails only when credential is missing or server rejects auth.
- Unknown host and changed host tests pass.
- No secret appears in logs, errors, terminal commands, or process args.

## Milestone 2: SFTP Packet Layer

Implement SFTP v3 packet framing:

```text
uint32 packetLength
byte   packetType
uint32 requestID
bytes  payload
```

Initial packet types:

- `SSH_FXP_INIT`
- `SSH_FXP_VERSION`
- `SSH_FXP_STATUS`
- `SSH_FXP_HANDLE`
- `SSH_FXP_NAME`
- `SSH_FXP_ATTRS`
- `SSH_FXP_OPENDIR`
- `SSH_FXP_READDIR`
- `SSH_FXP_CLOSE`
- `SSH_FXP_LSTAT`
- `SSH_FXP_STAT`
- `SSH_FXP_MKDIR`
- `SSH_FXP_REMOVE`
- `SSH_FXP_RMDIR`
- `SSH_FXP_RENAME`
- `SSH_FXP_OPEN`
- `SSH_FXP_READ`
- `SSH_FXP_WRITE`

Implementation tasks:

- Add `SFTPPacketEncoder`.
- Add `SFTPPacketDecoder`.
- Add request ID allocator.
- Add async request/response correlation actor.
- Map `SSH_FXP_STATUS` codes to `RemoteClientError`.
- Add binary unit tests using known packets.

Exit criteria:

- Version negotiation works.
- Packet encode/decode tests cover malformed length, unknown packet type, and status errors.

Status: partially complete. Packet encode/decode, request builders, status parsing, name parsing, and attribute parsing are implemented. Live version negotiation waits on Milestone 1 transport.

## Milestone 3: Directory Listing And Metadata

Expected behavior:

- `listDirectory` uses `OPENDIR`, repeated `READDIR`, then `CLOSE`.
- Converts SFTP names and attributes to `FileItem`.
- Applies `FileListPreferences` sorting/filtering locally.
- Supports hidden files toggle.

Implementation tasks:

- Implement SFTP attrs parser for size, permissions, owner/group ids if available, and modified date.
- Convert POSIX permission bits into `FileKind`.
- Add Docker integration test for listing `/config`.
- Add tests for empty folders, hidden files, folders first, and invalid path errors.

Exit criteria:

- Native backend lists Docker `/config`.
- UI can browse remote directories with native backend selected.

## Milestone 4: Remote File Operations

Expected behavior:

- Create folder.
- Rename.
- Delete files and folders.
- Existence check.

Implementation tasks:

- Implement `MKDIR`.
- Implement `RENAME`.
- Implement `REMOVE` and `RMDIR`; for recursive folder delete, explicitly walk children rather than issuing unsafe shell commands.
- Implement `LSTAT`/`STAT` for existence.
- Add path validation so empty/root destructive operations are rejected.

Exit criteria:

- Existing Docker integration test passes against native backend.
- Delete and overwrite behavior remains confirmation-driven in the UI.

## Milestone 5: Native Transfers

Expected behavior:

- Upload and download file streams with progress.
- Per-transfer cancellation closes outstanding handles and channels.
- Transfer progress reports bytes completed, total bytes, speed, and estimated remaining time where possible.

Implementation tasks:

- Add `SFTPTransferClient`.
- Implement `OPEN`, chunked `READ`, chunked `WRITE`, `CLOSE`.
- Use bounded chunk sizes, initially 32 KiB or 64 KiB.
- Throttle progress updates to avoid UI churn.
- Preserve timestamps only if setting is enabled and protocol attrs support it.
- Add conflict handling at the app layer before transfer.

Exit criteria:

- Docker upload/download tests pass. Implemented for files.
- Large-ish file test, e.g. 25-100 MB, passes without loading whole file into memory.
- Cancellation test confirms remote/local handles are closed. Initial Docker cancellation test covers pre-write cancellation and channel close.

## Milestone 6: Production Hardening

Security:

- No secret in logs.
- No password in process args.
- Host fingerprint changes block.
- Unknown hosts require explicit trust.
- Keychain failures map to actionable errors.

Reliability:

- Typed errors for auth failure, permission denied, no such file, disk full where detectable.
- Timeouts for connect and requests.
- Backpressure-aware streaming.
- Clean channel shutdown on disconnect.
- Reconnect semantics match current app behavior.

Performance:

- Avoid loading large files into memory.
- Avoid listing recursion unless requested.
- Add bounded transfer concurrency.
- Add Instruments checklist before release.

## Test Plan

Unit tests:

- Packet encode/decode.
- Attribute parsing.
- Error mapping.
- Request ID correlation.
- Host fingerprint formatting.
- Auth delegate missing credential behavior.

Integration tests:

- Docker private-key connect.
- Docker password connect if harness adds password mode.
- Host trust first-use and changed-host behavior.
- List/create/rename/delete.
- Upload/download.
- Cancel upload/download.

Manual QA:

- Use `docs/testing/manual-qa-checklist.md`.
- Test native backend from Settings against the Docker harness and one real SFTP server.

## Rollout Plan

1. Keep `System SSH` as default.
2. Hide native backend behind `Native Swift SSH` setting while integration tests mature.
3. When native listing and operations pass Docker tests, mark native backend beta.
4. When native transfers pass large-file and cancellation tests, make native backend default for password and private-key auth.
5. Keep system SSH fallback for one release cycle.

## Risks

- SFTP is a binary protocol; partial implementations can look correct while mishandling edge cases.
- Host-key conversion from `NIOSSHPublicKey` to existing trust records must be exact.
- SSH agent support may require additional platform-specific work.
- SwiftNIO event-loop lifecycle must be isolated from SwiftUI main-thread state.
- Password auth is only safer if it never leaks into logs, errors, or crash payloads.
