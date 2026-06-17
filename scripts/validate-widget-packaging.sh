#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT_DIR/dist/xcode/Driftline.app}"
PLUGIN_DIR="$APP/Contents/PlugIns"

fail() {
  echo "$1" >&2
  exit 2
}

/usr/bin/plutil -lint \
  "$ROOT_DIR/packaging/app/Driftline-Info.plist" \
  "$ROOT_DIR/packaging/entitlements/Driftline.entitlements" \
  "$ROOT_DIR/packaging/entitlements/DriftlineWidget.entitlements" \
  "$ROOT_DIR/packaging/widget/DriftlineWidget-Info.plist" >/dev/null

[[ -d "$APP" ]] || fail "Missing signed app: $APP. Run ./scripts/build-signed-xcode-app.sh."
[[ -d "$PLUGIN_DIR" ]] || fail "Missing PlugIns directory in app: $PLUGIN_DIR"

WIDGET=""
for candidate in "$PLUGIN_DIR/DriftlineWidget.appex" "$PLUGIN_DIR/DriftlineWidgetExtension.appex"; do
  [[ -d "$candidate" ]] && WIDGET="$candidate" && break
done
if [[ -z "$WIDGET" ]]; then
  WIDGET="$(/usr/bin/find "$PLUGIN_DIR" -maxdepth 1 -type d -name '*.appex' -print -quit)"
fi
[[ -n "$WIDGET" && -d "$WIDGET" ]] || fail "Missing embedded widget extension in: $PLUGIN_DIR"

APP_INFO="$APP/Contents/Info.plist"
WIDGET_INFO="$WIDGET/Contents/Info.plist"
[[ -f "$APP_INFO" ]] || fail "Missing app Info.plist: $APP_INFO"
[[ -f "$WIDGET_INFO" ]] || fail "Missing widget Info.plist: $WIDGET_INFO"

/usr/bin/plutil -lint "$APP_INFO" "$WIDGET_INFO" >/dev/null

EXTENSION_POINT="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$WIDGET_INFO" 2>/dev/null || true)"
[[ "$EXTENSION_POINT" == "com.apple.widgetkit-extension" ]] || fail "Wrong widget extension point: ${EXTENSION_POINT:-missing}"

/usr/bin/plutil -extract CFBundleURLTypes xml1 -o - "$APP_INFO" | /usr/bin/grep -q '<string>driftline</string>' || fail "Missing driftline URL scheme in app Info.plist."

APP_ENTITLEMENTS="$(mktemp)"
WIDGET_ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$APP_ENTITLEMENTS" "$WIDGET_ENTITLEMENTS"' EXIT

/usr/bin/codesign --verify --deep --strict "$APP" || fail "App codesign verification failed: $APP"
/usr/bin/codesign --verify --strict "$WIDGET" || fail "Widget codesign verification failed: $WIDGET"
/usr/bin/codesign -d --entitlements :- "$APP" >"$APP_ENTITLEMENTS" 2>/dev/null || fail "Missing signed app entitlements: $APP"
/usr/bin/codesign -d --entitlements :- "$WIDGET" >"$WIDGET_ENTITLEMENTS" 2>/dev/null || fail "Missing signed widget entitlements: $WIDGET"

APP_GROUP="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$APP_ENTITLEMENTS" 2>/dev/null || true)"
WIDGET_GROUP="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$WIDGET_ENTITLEMENTS" 2>/dev/null || true)"

[[ -n "$APP_GROUP" ]] || fail "Missing App Group entitlement on app."
[[ "$APP_GROUP" == "$WIDGET_GROUP" ]] || fail "App/widget App Group mismatch."
[[ "$APP_GROUP" == group.* ]] || fail "Invalid App Group entitlement: $APP_GROUP"
[[ "$APP_GROUP" != *'$('* && "$APP_GROUP" != *"<"* && "$APP_GROUP" != *"example"* && "$APP_GROUP" != *"placeholder"* ]] || fail "Placeholder App Group in signed output."

echo "Widget packaging validated."
echo "App: $APP"
echo "Widget: $WIDGET"
