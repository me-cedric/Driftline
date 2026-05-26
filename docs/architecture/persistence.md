# Persistence

Sensitive values are never stored in profile records. Saved profiles store `CredentialReference` values pointing at Keychain entries.

## Current Approach

The code currently uses JSON repositories for non-sensitive early app data:

- `JSONServerProfileRepository`
- `JSONHostTrustStore`
- `JSONTransferHistoryRepository`
- `JSONViewPreferencesRepository`

Files are stored in `~/Library/Application Support/Driftline/`.

This is intentionally small and inspectable for the early milestone. The repository protocols keep the app ready to migrate to:

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

## Migration Considerations

JSON storage is acceptable while schemas are small and pre-1.0. Before stable releases, add:

- schema version fields
- migration tests
- corruption recovery behavior
- optional export/import format separate from internal persistence
