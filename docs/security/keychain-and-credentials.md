# Keychain And Credentials

Driftline stores passwords and passphrases in macOS Keychain through `CredentialStore`.

Server profiles store only:

- service identifier
- account identifier
- authentication method metadata

They do not store raw secret bytes.

The app must never accept passwords through CLI arguments or write them into terminal commands.

## Backend Behavior

- The default system SSH backend supports SSH agent and private-key workflows.
- Password credentials can be saved in Keychain today.
- Password-based file browsing is blocked in the default backend because injecting passwords into shell commands or process arguments would be unsafe.
- The experimental native Swift backend retrieves password credentials through `CredentialStore`; it remains guarded until the SFTP subsystem is implemented on top of SwiftNIO SSH.
