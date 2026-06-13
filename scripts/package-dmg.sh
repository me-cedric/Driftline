#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/dist/Driftline.app"
DMG="$ROOT_DIR/dist/Driftline.dmg"

DRIFTLINE_BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --verify
pkill -x Driftline >/dev/null 2>&1 || true

mkdir -p "$ROOT_DIR/dist"
hdiutil create -volname Driftline -srcfolder "$APP" -ov -format UDZO "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"
echo "Created $DMG"
