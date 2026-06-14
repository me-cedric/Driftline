#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/dist/Driftline.app"
DMG="$ROOT_DIR/dist/Driftline.dmg"
SHA="$DMG.sha256"
PLIST="$APP/Contents/Info.plist"

test -d "$APP"
test -f "$APP/Contents/MacOS/Driftline"
test -f "$PLIST"
test -f "$DMG"
test -f "$SHA"

shasum -a 256 -c "$SHA"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"

if [[ "$BUNDLE_ID" != "app.driftline.Driftline" ]]; then
  echo "Unexpected bundle id: $BUNDLE_ID" >&2
  exit 1
fi

if [[ -n "${DRIFTLINE_SIGN_IDENTITY:-}" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  echo "Signing identity not set; artifact is unsigned or ad-hoc signed."
fi

cat <<EOF
Artifact verified:
  app: $APP
  dmg: $DMG
  version: $VERSION
  build: $BUILD
EOF
