#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BACKEND="${DRIFTLINE_REAL_SERVER_BACKEND:-all}"
REMOTE_PATH="${DRIFTLINE_TEST_REMOTE_PATH:-/config}"
PORT="${DRIFTLINE_TEST_PORT:-22}"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "$name is required." >&2
    exit 2
  fi
}

restore_tty() {
  stty echo >/dev/null 2>&1 || true
}

case "$BACKEND" in
  system|native|all) ;;
  *)
    echo "DRIFTLINE_REAL_SERVER_BACKEND must be system, native, or all." >&2
    exit 2
    ;;
esac

require_env DRIFTLINE_TEST_HOST
require_env DRIFTLINE_TEST_USER

if [[ "$BACKEND" == "system" || "$BACKEND" == "all" ]]; then
  require_env DRIFTLINE_TEST_KEY
  export DRIFTLINE_INTEGRATION_SFTP=1
fi

if [[ "$BACKEND" == "native" || "$BACKEND" == "all" ]]; then
  if [[ -z "${DRIFTLINE_TEST_PASSWORD:-}" ]]; then
    printf "DRIFTLINE_TEST_PASSWORD: " >&2
    trap restore_tty EXIT
    if [[ -t 0 ]]; then
      stty -echo
    fi
    IFS= read -r DRIFTLINE_TEST_PASSWORD
    restore_tty
    trap - EXIT
    printf "\n" >&2
  fi
  if [[ -z "${DRIFTLINE_TEST_PASSWORD:-}" ]]; then
    echo "DRIFTLINE_TEST_PASSWORD is required for native backend QA." >&2
    exit 2
  fi
  export DRIFTLINE_TEST_PASSWORD
  export DRIFTLINE_NATIVE_INTEGRATION_SFTP=1
fi

export DRIFTLINE_TEST_PORT="$PORT"
export DRIFTLINE_TEST_REMOTE_PATH="$REMOTE_PATH"

echo "== Driftline real-server SFTP QA =="
echo "Target: ${DRIFTLINE_TEST_USER}@${DRIFTLINE_TEST_HOST}:${DRIFTLINE_TEST_PORT}"
echo "Remote test root: ${DRIFTLINE_TEST_REMOTE_PATH}"
echo "Backend mode: ${BACKEND}"
echo "Password: $(if [[ -n "${DRIFTLINE_TEST_PASSWORD:-}" ]]; then echo configured; else echo not-used; fi)"
echo "Private key: $(if [[ -n "${DRIFTLINE_TEST_KEY:-}" ]]; then echo configured; else echo not-used; fi)"
echo
echo "Remote test root must already exist and be writable."
echo "Tests create, rename, transfer, and delete driftline-* items inside that root."
echo

swift test --filter SFTPIntegrationTests
