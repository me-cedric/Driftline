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
- The experimental native Swift backend retrieves password and private-key passphrase credentials through `CredentialStore` and performs SFTP operations in-process through SwiftNIO SSH.
- Native SSH agent authentication is not available through SwiftNIO SSH 0.11.0; use the System SSH backend for agent-based auth.
