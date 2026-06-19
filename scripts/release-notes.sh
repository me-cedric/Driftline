#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
VERSION="${VERSION#v}"

if [[ -z "$VERSION" ]]; then
  VERSION="$(sed -n 's/^let version = "\(.*\)"/\1/p' "$ROOT_DIR/Sources/driftline/main.swift" | head -1)"
fi

if [[ -n "$VERSION" ]]; then
  awk -v header="## $VERSION" '
    /^## / {
      if (found) { exit }
      found = index($0, header) == 1
    }
    found { print }
  ' "$ROOT_DIR/CHANGELOG.md"
else
  awk '
    /^## / {
      if (found) { exit }
      found = 1
    }
    found { print }
  ' "$ROOT_DIR/CHANGELOG.md"
fi
