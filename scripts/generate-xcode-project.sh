#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required to generate Driftline.xcodeproj." >&2
  echo "Install: brew install xcodegen" >&2
  exit 2
fi

cd "$ROOT_DIR"
xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
echo "Generated $ROOT_DIR/Driftline.xcodeproj"
