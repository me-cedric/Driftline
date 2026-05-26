# Protocol Adapters

All remote backends conform to `RemoteFileSystemClient`. Transfer execution will use `TransferClient`.

## SFTP

SFTP is the first production protocol. The current implementation uses system SSH tooling for agent/private-key profiles:

- `ssh-keyscan` and `ssh-keygen` for host fingerprint lookup.
- `ssh` plus a strict `find -printf` command for remote listing.
- `rsync` over SSH for upload/download with live progress parsing.
- `scp` as a simpler fallback transfer backend.

The adapter boundary still allows:

- `/usr/bin/sftp` batch mode with strict process control and parsing.
- Future SwiftNIO SSH or libssh2-backed implementation.
- Host trust verification before browsing or transfer.

Password profiles are saved as Keychain references, but password authentication is not passed into system SSH commands because that would risk exposing secrets.

## Native Swift SSH/SFTP

`NativeSFTPClient` is selectable through settings as an experimental backend. It currently:

- depends on Apple SwiftNIO SSH for the native SSH foundation;
- retrieves password and private-key passphrase credentials through `CredentialStore`;
- supports password auth, OpenSSH Ed25519 private-key auth, passphrase-protected OpenSSH Ed25519 keys, and ECDSA PEM keys;
- supports native SFTP listing, create folder, rename, recursive delete, existence checks, file upload/download, folder upload/download, progress, and cancellation;
- keeps the stable system SSH backend as the default while the native backend receives broader real-server testing.

SSH agent signing remains on the System SSH backend. Driftline includes a native agent protocol client for discovery/list/sign primitives, but SwiftNIO SSH 0.11.0 does not expose a custom agent-backed signer hook for user authentication.

The implementation plan lives in [native-swift-sftp-plan.md](native-swift-sftp-plan.md).

## FTP / FTPS

FTP and FTPS are scaffolded as unsupported adapters until:

- TLS certificate handling is designed.
- Passive/active mode behavior is tested.
- Credentials and logs are redacted.
- Integration tests exist.
