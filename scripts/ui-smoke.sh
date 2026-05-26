#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/script/build_and_run.sh" --verify
pkill -x Driftline >/dev/null 2>&1 || true
echo "UI smoke check passed: Driftline app bundle launched."
