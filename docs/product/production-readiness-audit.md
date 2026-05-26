# Production Readiness Audit

Last reviewed: 2026-05-26.

## Wired And Functional

- Saved servers: create, edit, duplicate, delete, favorite, select, connect, and persist.
- Bookmarks and recents: saved to JSON repositories and shown in the sidebar. Bookmarks appear after a real connection is saved with "Bookmark" or "Save Current Connection".
- Credentials: passwords and private-key passphrases are stored through `CredentialStore`; persisted profiles store references only.
- Local browser: list, sort, hide dotfiles, navigate, create folder, rename, delete, reveal/open path flows.
- Remote SFTP browser: System SSH backend for agent/private-key profiles; native Swift backend for password and supported private-key profiles.
- Native SFTP transfers: file upload/download, recursive folder upload/download, progress callbacks, cancellation, large-file round-trip coverage, and recursive remote delete.
- CLI: `driftline .`, `--open`, `--new-tab`, `--bookmark`, `--help`, and `--version` parse safely and never accept secrets.
- Release scaffolding: app icon, app bundle, DMG packaging, checksums, signing/notarization scripts, GitHub workflows, and Homebrew documentation.

## Intentional Non-Production Defaults

- Native Swift SFTP remains opt-in from Settings while it receives broader real-server testing. System SSH remains the default stable backend.
- FTP and FTPS remain unsupported by code. They are documented as protocol-roadmap items because FTPS certificate validation and FTP mode handling need dedicated security work.
- SSH agent auth for the native Swift backend is not claimed complete. Driftline has a native agent protocol client, but SwiftNIO SSH 0.11.0 does not expose an agent-backed authentication signer hook. Use the System SSH backend for agent-based auth today.
- Signing and notarization are documented but cannot be completed without Apple Developer credentials configured through `DRIFTLINE_SIGN_IDENTITY` and `DRIFTLINE_NOTARY_PROFILE`.
- Manual VoiceOver, high-contrast, and real-server security QA are still required before a public 1.0 release.

## Placeholder Sweep Results

- No fake sample server or fake transfer queue is seeded in the app.
- Asset names no longer use "placeholder" for active README/app branding. `assets/app-icon-concept.svg` remains as source artwork documentation; `assets/app-icon-1024.png`, `assets/Driftline.icns`, and `assets/banner.svg` are the active assets.
- Remaining "planned", "future", and "unsupported" language is limited to explicit roadmap, release, or protocol-scope documentation.
- Code paths that are intentionally unavailable return typed `RemoteClientError` values rather than silent no-ops.
