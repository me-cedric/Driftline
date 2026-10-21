# Host Verification

SFTP connections must verify host identity before use.

Flow:

1. Fetch presented host key fingerprint.
2. Compare with `HostTrustStore`.
3. If unknown, show fingerprint and require explicit trust.
4. If changed, block connection and present a high-severity warning.
5. If trusted, allow connection.

The current implementation includes the domain model, verification result enum, durable JSON host trust store, `ssh-keyscan`/`ssh-keygen` fingerprint lookup, first-use trust sheet, changed-fingerprint blocking, and a Driftline-managed `known_hosts` file.

SSH/SCP commands run with `UserKnownHostsFile=<Application Support>/Driftline/known_hosts`, `GlobalKnownHostsFile=/dev/null`, and `StrictHostKeyChecking=yes`.

The System SSH backend scans a host key (`ssh-keyscan`) only when ssh reports an unknown or changed key. Each scan opens unauthenticated connections, and OpenSSH 9.8+ servers block a source address that opens many (`PerSourcePenalties`).

Server detection in the editor opens short connections before any trust decision: it reads the SSH banner or the FTP greeting, asks AUTH TLS, and runs one `ssh` with the "none" login to list the login methods. It uses `StrictHostKeyChecking=no` with `/dev/null` known hosts and accepts any TLS certificate, because it sends no credential and no file. The real connection then checks the host key or certificate as described here.

FTPS certificates that macOS trusts are accepted. For any other certificate (self-signed, wrong name), Driftline shows the SHA-256 certificate fingerprint in the same trust sheet and stores the decision as algorithm `TLS`. A later certificate with another fingerprint is blocked as a changed fingerprint.
