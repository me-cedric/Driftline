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
