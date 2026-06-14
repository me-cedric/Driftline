#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Driftline release readiness =="
swift test
swift build -c release
DRIFTLINE_BUILD_CONFIGURATION=release ./scripts/ui-smoke.sh
./scripts/package-dmg.sh
./scripts/verify-artifacts.sh

echo "== Artifact =="
test -f dist/Driftline.dmg
test -f dist/Driftline.dmg.sha256
test -f dist/Driftline.release.json
cat dist/Driftline.dmg.sha256

echo "== Signing status =="
if [[ -n "${DRIFTLINE_SIGN_IDENTITY:-}" ]]; then
  codesign --verify --deep --strict --verbose=2 dist/Driftline.app
else
  echo "DRIFTLINE_SIGN_IDENTITY is not set; build is local unsigned/dev-signed only."
fi

echo "== Notarization status =="
if [[ -n "${DRIFTLINE_NOTARY_PROFILE:-}" ]]; then
  ./scripts/notarize.sh
else
  echo "DRIFTLINE_NOTARY_PROFILE is not set; notarization was not attempted."
fi

echo "Release readiness checks completed."
