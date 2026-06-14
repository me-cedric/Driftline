# Distribution

## Planned Release Flow

1. Run tests.
2. Build release app.
3. Package `Driftline.app` into `Driftline.dmg`.
4. Code sign.
5. Notarize.
6. Generate checksum.
7. Publish GitHub Release.
8. Update Homebrew formula.

`scripts/package-dmg.sh` builds a release SwiftPM app bundle, creates `dist/Driftline.dmg`, and writes a SHA-256 checksum.

Signing and notarization still require developer credentials and must not be claimed complete until configured.

Run `./scripts/release-check.sh` before publishing a release.

## Signing And Notarization Setup

Driftline uses two environment variables for local release signing:

- `DRIFTLINE_SIGN_IDENTITY`: the exact Developer ID Application identity visible to `codesign`.
- `DRIFTLINE_NOTARY_PROFILE`: the local `notarytool` keychain profile name.

### Get `DRIFTLINE_SIGN_IDENTITY`

You need an active Apple Developer Program membership and a Developer ID Application certificate.

1. Create or download a Developer ID Application certificate from Apple Developer Certificates.
2. Install it into the macOS login keychain. It must appear in Keychain Access under "My Certificates" with a private key below it.
3. List usable signing identities:

```bash
security find-identity -v -p codesigning
```

4. Use the full identity string, for example:

```bash
export DRIFTLINE_SIGN_IDENTITY="Developer ID Application: Example Company, Inc. (TEAMID1234)"
```

### Get `DRIFTLINE_NOTARY_PROFILE`

Create a keychain profile with `notarytool`. The profile name is arbitrary; `driftline-notary` is a good default.

```bash
xcrun notarytool store-credentials "driftline-notary" \
  --apple-id "developer@example.com" \
  --team-id "TEAMID1234" \
  --password "app-specific-password"
```

Then export:

```bash
export DRIFTLINE_NOTARY_PROFILE="driftline-notary"
```

The password should be an app-specific password or App Store Connect API credentials, not a password committed to this repository.

### Validate A Release Locally

```bash
DRIFTLINE_SIGN_IDENTITY="Developer ID Application: Example Company, Inc. (TEAMID1234)" \
DRIFTLINE_NOTARY_PROFILE="driftline-notary" \
./scripts/release-check.sh
```

Do not claim a release is signed or notarized unless `codesign --verify`, `notarytool submit --wait`, and stapling all succeed.

## Icon Workflow

`assets/app-icon-1024.png` and `assets/app-icon-dark-1024.png` are the canonical app icon sources from the Driftline icon pack. To refresh generated icon assets, replace those PNGs with 1024x1024 exports from the icon pack, then run:

```bash
./scripts/generate-iconset.sh
```

The script refreshes the local `.iconset` folders and creates `assets/Driftline.icns` plus `assets/DriftlineDark.icns`. The SwiftPM app wrapper copies both icons into `Contents/Resources`; `CFBundleIconFile` keeps the light icon as the bundle default, while the in-app setting can switch the runtime Dock icon.

## Smoke Test

```bash
./scripts/ui-smoke.sh
```

This builds the app bundle, launches it, verifies the process starts, and closes it.
