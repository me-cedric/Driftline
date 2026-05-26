#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_PNG="${1:-$ROOT_DIR/assets/app-icon-1024.png}"
ICONSET="$ROOT_DIR/assets/Driftline.iconset"
ICNS="$ROOT_DIR/assets/Driftline.icns"

if [[ ! -f "$SOURCE_PNG" ]]; then
  echo "Provide a 1024x1024 PNG at $SOURCE_PNG or pass a path as the first argument." >&2
  echo "The SVG concept lives at assets/app-icon-concept.svg." >&2
  exit 2
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16 "$SOURCE_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$SOURCE_PNG" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "Created $ICNS"
