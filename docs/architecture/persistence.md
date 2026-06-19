# Persistence

Sensitive values are never stored in profile records. Saved profiles store `CredentialReference` values pointing at Keychain entries.

## Current Approach

The code currently uses JSON repositories for non-sensitive early app data:

- `JSONServerProfileRepository`
- `JSONHostTrustStore`
- `JSONTransferHistoryRepository`
- `JSONViewPreferencesRepository`

Files are stored in `~/Library/Application Support/Driftline/`.

This is intentionally small and inspectable for the 1.0 line. The repository protocols keep the app ready to migrate to:

- SwiftData for native app simplicity and future migrations.
- SQLite for explicit schema control and portable test fixtures.

## Data Classes

- Saved servers without secrets.
- Bookmarks and recent servers.
- View preferences.
- Transfer history.
- Host trust records.
- Stats.
- Last paths and window state.

## 1.0 Schema Freeze

Current files:

- `server-profiles.json`: non-secret server profiles and credential references.
- `host-trust.json`: trusted host fingerprints.
- `transfer-history.json`: transfer status, paths, backend/profile identity, timestamps, and byte counts.
- `preferences.json`: view, backend, update-check, notification, language, and appearance settings.
- `bookmarks.json`: saved local/remote path pairs.
- `recent-servers.json`: recent non-secret connection metadata.
- `mcp.json`: local MCP settings.
- `integration-snapshot.json`: non-secret local integration state.
- `known_hosts`: Driftline-managed SSH host keys.

Rules after this freeze:

- Add a migration test for any added, renamed, or removed persisted field.
- Decode missing fields with safe defaults.
- Never persist raw secrets.
- Keep export/import separate from internal persistence.
- Move corrupted JSON to a `.corrupt-*` file and load defaults instead of failing app startup.

## Later Migration Considerations

JSON storage is acceptable while schemas are small. If persisted data grows beyond simple JSON repositories, migrate behind the existing repository protocols and add:

- schema version fields
- migration tests for old payloads
- corruption recovery behavior
- optional export/import format separate from internal persistence
