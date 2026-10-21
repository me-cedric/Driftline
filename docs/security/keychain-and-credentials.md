# Keychain And Credentials

Driftline stores passwords and passphrases in macOS Keychain through `CredentialStore`.

Server profiles store only:

- service identifier
- account identifier
- authentication method metadata

They do not store raw secret bytes.

The app must never accept passwords through CLI arguments or write them into terminal commands.

## Backend Behavior

- The default system SSH backend supports SSH agent, private-key, password and keyboard-interactive workflows.
- For a password or a stored key passphrase, Driftline sets `SSH_ASKPASS` to a helper script in a private 0700 temporary folder. The script reads a FIFO, and Driftline writes the secret into the FIFO only when ssh asks. The secret is never in a command argument, an environment value or a file. `NumberOfPasswordPrompts=1` limits failed attempts per connection.
- FTP and FTPS read the password from `CredentialStore` and send it only on the control connection (TLS for FTPS). Plain FTP sends it unencrypted; the server editor warns about this.
- The experimental native Swift backend retrieves password and private-key passphrase credentials through `CredentialStore` and performs SFTP operations in-process through SwiftNIO SSH.
- Native SSH agent authentication is not available through SwiftNIO SSH 0.11.0; use the System SSH backend for agent-based auth.
