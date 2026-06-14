#!/usr/bin/env bash
set -euo pipefail

echo "=== SwiftLint (via SwiftPM plugin) ==="
swift package plugin --allow-writing-to-package-directory swiftlint 2>&1 || {
  echo "SwiftLint found violations. Fix them before committing."
  exit 1
}

echo ""
echo "=== SwiftFormat (via SwiftPM plugin) ==="
BEFORE_FORMAT="$(mktemp)"
AFTER_FORMAT="$(mktemp)"
trap 'rm -f "$BEFORE_FORMAT" "$AFTER_FORMAT"' EXIT

format_snapshot() {
  find Package.swift Sources Tests -type f -name '*.swift' -print0 \
    | sort -z \
    | xargs -0 shasum
}

format_snapshot >"$BEFORE_FORMAT"
swift package plugin --allow-writing-to-package-directory swiftformat 2>&1
format_snapshot >"$AFTER_FORMAT"

# After formatting, check if SwiftFormat changed the working tree during this run.
if ! cmp -s "$BEFORE_FORMAT" "$AFTER_FORMAT"; then
  echo ""
  echo "ERROR: SwiftFormat modified files."
  echo "Run './scripts/lint.sh' locally and commit the formatted files."
  exit 1
fi

echo "All files are properly formatted."
echo ""
echo "All lint checks passed."
