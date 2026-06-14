#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/dist/Driftline.app"
DMG="$ROOT_DIR/dist/Driftline.dmg"
MANIFEST="$ROOT_DIR/dist/Driftline.release.json"

DRIFTLINE_BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --verify
pkill -x Driftline >/dev/null 2>&1 || true

mkdir -p "$ROOT_DIR/dist"
hdiutil create -volname Driftline -srcfolder "$APP" -ov -format UDZO "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
SHA256="$(cut -d ' ' -f 1 "$DMG.sha256")"
SIGNED="false"
if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  SIGNED="true"
fi
cat >"$MANIFEST" <<JSON
{
  "name": "Driftline",
  "version": "$VERSION",
  "build": "$BUILD",
  "dmg": "Driftline.dmg",
  "sha256": "$SHA256",
  "signed": $SIGNED
}
JSON
echo "Created $DMG"
echo "Created $MANIFEST"
