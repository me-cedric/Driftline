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

`scripts/package-dmg.sh` builds the SwiftPM app bundle, creates `dist/Driftline.dmg`, and writes a SHA-256 checksum.

Signing and notarization still require developer credentials and must not be claimed complete until configured.

Run `./scripts/release-check.sh` before publishing a release.

## Icon Workflow

`assets/app-icon-placeholder.svg` contains the icon concept. Export a 1024x1024 PNG to `assets/app-icon-1024.png`, then run:

```bash
./scripts/generate-iconset.sh
```

The script creates `assets/Driftline.icns`. The SwiftPM app wrapper copies it into `Contents/Resources` when present and declares it through `CFBundleIconFile`.

## Smoke Test

```bash
./scripts/ui-smoke.sh
```

This builds the app bundle, launches it, verifies the process starts, and closes it.
