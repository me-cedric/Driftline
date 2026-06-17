# Raycast Integration

Driftline includes a first Raycast extension at `apps/raycast-extension`.

## Repo Strategy

The extension is kept inside this repository as an isolated monorepo package. Driftline is still SwiftPM-first, and the Raycast package keeps Node dependencies, scripts, generated files, and TypeScript source under `apps/raycast-extension` so native macOS build settings remain untouched.

## Setup

```bash
cd apps/raycast-extension
npm install
npm run dev
```

Use `npm run build`, `npm run typecheck`, and `npm run lint` for validation.

The manifest `author` field must be a valid Raycast Store handle for `ray lint`; replace the placeholder with the maintainer handle before any store submission.

## Bundle ID

The default Driftline bundle id is `app.driftline.Driftline`, matching `script/build_and_run.sh` and the product branding docs. If a local build uses another identifier, update the extension preference named `Driftline Bundle ID` in Raycast.

## Commands

- `Open Driftline`: no-view command that opens the installed Driftline app.
- `Quick Connect`: form command for protocol, host, port, username, and optional path.
- `Recent Connections`: list command backed by Raycast LocalStorage until Raycast reads Driftline's native non-secret integration summaries.
- `Driftline Status`: menu bar command showing app installed status and local extension status until Raycast reads Driftline's native status snapshot.

## Deep Link Contract

Driftline registers the `driftline` URL scheme in the generated app bundle and handles this connection handoff:

```text
driftline://connect?protocol=sftp&host=example.com&port=22&username=user&path=/optional/path
```

Rules:

- URL encode all values.
- Do not include passwords, private keys, passphrases, tokens, or other secrets.
- Driftline accepts SFTP links only.
- Driftline requires `host`, numeric `port` in `1...65535`, and `username`.
- `path` is optional and pre-fills the remote path.
- Driftline ignores secret-like query fields and shows a safe warning if they appear.
- Keep unsupported fields out of the URL.
- Driftline opens the Quick Connect/profile creation sheet and pre-fills fields. It does not auto-connect from a URL.

Manual test:

```bash
open 'driftline://connect?protocol=sftp&host=example.com&port=22&username=test&path=%2F'
```

## Current Limitations

- Raycast recents are local extension storage, not Driftline profile or favorite data. Driftline now has native non-secret recents/favorites summary models for future Raycast, App Intent, and WidgetKit wiring.
- Passwords are unsupported in v1. Credentials must stay in Driftline `CredentialStore` or a future Raycast password preference flow.
- Driftline now has a native non-secret transfer status snapshot model. Raycast still needs a transport before its menu bar command can read it.

## Native Next Steps

- Add a native App Intent or App Group transport so Raycast/widgets can read Driftline's sanitized recents/favorites and status snapshot.
- Add a WidgetKit target after signing/team App Group configuration is chosen.
- Keep all credential entry inside Driftline's `CredentialStore`; URLs and shared integration state must remain non-secret.
