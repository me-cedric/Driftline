#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Driftline.xcodeproj"
LOCAL_SIGNING="$ROOT_DIR/packaging/config/DriftlineSigning.xcconfig"
CONFIGURATION="${1:-${CONFIGURATION:-Debug}}"
OUT_DIR="$ROOT_DIR/dist/xcode"
DERIVED_DATA="$OUT_DIR/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/Driftline.app"
APP_OUT="$OUT_DIR/Driftline.app"

fail() {
  echo "$1" >&2
  exit 2
}

xcconfig_value() {
  /usr/bin/awk -F= -v key="$1" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value=$2
      sub(/[[:space:]]*\/\/.*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$LOCAL_SIGNING"
}

[[ "$CONFIGURATION" == "Debug" || "$CONFIGURATION" == "Release" ]] || fail "Unsupported configuration: $CONFIGURATION"
[[ -d "$PROJECT" ]] || fail "Missing generated project: $PROJECT. Run ./scripts/generate-xcode-project.sh."
[[ -f "$LOCAL_SIGNING" ]] || fail "Missing local signing config: $LOCAL_SIGNING. Copy packaging/config/DriftlineSigning.xcconfig.template and fill it locally."

TEAM_ID="$(xcconfig_value DEVELOPMENT_TEAM)"
APP_GROUP="$(xcconfig_value DRIFTLINE_APP_GROUP_IDENTIFIER)"

missing=()
[[ -n "$TEAM_ID" && "$TEAM_ID" != *"<"* && "$TEAM_ID" != *"example"* ]] || missing+=("DEVELOPMENT_TEAM")
[[ "$APP_GROUP" == group.* ]] || missing+=("DRIFTLINE_APP_GROUP_IDENTIFIER")
[[ "$APP_GROUP" != *'$('* && "$APP_GROUP" != *"<"* && "$APP_GROUP" != *"example"* && "$APP_GROUP" != *"placeholder"* ]] || missing+=("non-placeholder DRIFTLINE_APP_GROUP_IDENTIFIER")
if (( ${#missing[@]} > 0 )); then
  echo "Missing local signing config values in $LOCAL_SIGNING:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme Driftline \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

[[ -d "$BUILT_APP" ]] || fail "Build finished but app missing: $BUILT_APP"

rm -rf "$APP_OUT"
/usr/bin/ditto "$BUILT_APP" "$APP_OUT"
/usr/bin/codesign --verify --deep --strict "$APP_OUT" || fail "Signed app verification failed: $APP_OUT"

echo "Signed app: $APP_OUT"
