#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG="${1:-$ROOT_DIR/dist/Driftline.dmg}"

if [[ ! -f "$DMG" ]]; then
  echo "DMG not found at $DMG" >&2
  exit 2
fi

if [[ -z "${DRIFTLINE_NOTARY_PROFILE:-}" ]]; then
  echo "Set DRIFTLINE_NOTARY_PROFILE to a notarytool keychain profile to notarize." >&2
  exit 2
fi

xcrun notarytool submit "$DMG" --keychain-profile "$DRIFTLINE_NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
