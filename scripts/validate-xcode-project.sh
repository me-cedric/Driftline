#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Driftline.xcodeproj"
LOCAL_SIGNING="$ROOT_DIR/packaging/config/DriftlineSigning.xcconfig"

"$ROOT_DIR/scripts/generate-xcode-project.sh"

if [[ ! -d "$PROJECT" ]]; then
  echo "Missing generated project: $PROJECT" >&2
  exit 2
fi

xcodebuild -project "$PROJECT" -list

app_group_configured() {
  [[ -n "${DRIFTLINE_APP_GROUP_IDENTIFIER:-}" ]] && return 0
  [[ -f "$LOCAL_SIGNING" ]] && /usr/bin/grep -Eq '^[[:space:]]*DRIFTLINE_APP_GROUP_IDENTIFIER[[:space:]]*=[[:space:]]*[^[:space:]$]' "$LOCAL_SIGNING"
}

build_setting_args=()
if [[ -n "${DRIFTLINE_APP_GROUP_IDENTIFIER:-}" ]]; then
  build_setting_args+=("DRIFTLINE_APP_GROUP_IDENTIFIER=$DRIFTLINE_APP_GROUP_IDENTIFIER")
fi
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  build_setting_args+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi

if [[ "${DRIFTLINE_XCODE_SIGN:-0}" == "1" ]]; then
  if ! app_group_configured; then
    echo "Set DRIFTLINE_APP_GROUP_IDENTIFIER in env or packaging/config/DriftlineSigning.xcconfig before signed widget builds." >&2
    exit 2
  fi
else
  build_setting_args+=("CODE_SIGNING_ALLOWED=NO")
  echo "Unsigned compile validation. Set DRIFTLINE_XCODE_SIGN=1 plus signing/App Group config for signed app/widget builds."
fi

build_scheme() {
  local scheme="$1"
  local log
  log="$(mktemp)"
  if ! xcodebuild \
    -project "$PROJECT" \
    -scheme "$scheme" \
    -configuration Debug \
    -destination 'platform=macOS' \
    build \
    "${build_setting_args[@]}" >"$log" 2>&1; then
    tail -n 80 "$log" >&2
    rm -f "$log"
    echo "Xcode build failed for $scheme. If this was signed mode, check DEVELOPMENT_TEAM, provisioning profiles, and DRIFTLINE_APP_GROUP_IDENTIFIER." >&2
    exit 2
  fi
  rm -f "$log"
}

build_scheme Driftline
build_scheme DriftlineWidgetExtension
build_scheme DriftlineCore
build_scheme DriftlineWidget

echo "Xcode project validated."
