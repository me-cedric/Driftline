#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_PNG="${1:-$ROOT_DIR/assets/app-icon-1024.png}"
SOURCE_DARK_PNG="${2:-$ROOT_DIR/assets/app-icon-dark-1024.png}"
ICONSET="$ROOT_DIR/assets/Driftline.iconset"
ICNS="$ROOT_DIR/assets/Driftline.icns"
ICONSET_DARK="$ROOT_DIR/assets/DriftlineDark.iconset"
ICNS_DARK="$ROOT_DIR/assets/DriftlineDark.icns"

if [[ ! -f "$SOURCE_PNG" ]]; then
  echo "Provide a 1024x1024 PNG at $SOURCE_PNG or pass a path as the first argument." >&2
  echo "Use the 1024px PNG from the Driftline icon pack as assets/app-icon-1024.png." >&2
  exit 2
fi

generate_icon() {
  local source_png="$1"
  local iconset="$2"
  local icns="$3"

  rm -rf "$iconset"
  mkdir -p "$iconset"

  sips -z 16 16 "$source_png" --out "$iconset/icon_16x16.png" >/dev/null
  sips -z 32 32 "$source_png" --out "$iconset/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$source_png" --out "$iconset/icon_32x32.png" >/dev/null
  sips -z 64 64 "$source_png" --out "$iconset/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$source_png" --out "$iconset/icon_128x128.png" >/dev/null
  sips -z 256 256 "$source_png" --out "$iconset/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$source_png" --out "$iconset/icon_256x256.png" >/dev/null
  sips -z 512 512 "$source_png" --out "$iconset/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$source_png" --out "$iconset/icon_512x512.png" >/dev/null
  cp "$source_png" "$iconset/icon_512x512@2x.png"

  iconutil -c icns "$iconset" -o "$icns"
  echo "Created $icns"
}

generate_icon "$SOURCE_PNG" "$ICONSET" "$ICNS"

if [[ -f "$SOURCE_DARK_PNG" ]]; then
  generate_icon "$SOURCE_DARK_PNG" "$ICONSET_DARK" "$ICNS_DARK"
fi
