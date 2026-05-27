#!/usr/bin/env bash
set -euo pipefail

echo "=== SwiftLint (via SwiftPM plugin) ==="
swift package plugin --allow-writing-to-package-directory swiftlint 2>&1 || {
  echo "SwiftLint found violations. Fix them before committing."
  exit 1
}

echo ""
echo "=== SwiftFormat (via SwiftPM plugin) ==="
swift package plugin --allow-writing-to-package-directory swiftformat 2>&1

# After formatting, check if any files were changed (fails CI if unformatted code exists)
if ! git diff --exit-code --stat; then
  echo ""
  echo "ERROR: SwiftFormat modified files above."
  echo "Run './scripts/lint.sh' locally and commit the formatted files."
  exit 1
fi

echo "All files are properly formatted."
echo ""
echo "All lint checks passed."
