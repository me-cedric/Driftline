#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-start}"
NAME="driftline-sftp-test"
PORT="${DRIFTLINE_TEST_SSH_PORT:-22222}"
PASSWORD="${DRIFTLINE_TEST_PASSWORD:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_DIR="$ROOT_DIR/.integration/ssh"
KEY_PATH="$KEY_DIR/id_ed25519"

case "$MODE" in
  start)
    command -v docker >/dev/null || {
      echo "Docker is required for the integration SFTP server." >&2
      exit 2
    }
    mkdir -p "$KEY_DIR"
    if [[ ! -f "$KEY_PATH" ]]; then
      ssh-keygen -t ed25519 -N "" -f "$KEY_PATH" -q
    fi
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    if [[ -n "$PASSWORD" ]]; then
      docker run -d --name "$NAME" \
        -p "$PORT:2222" \
        -e SUDO_ACCESS=false \
        -e PASSWORD_ACCESS=true \
        -e USER_NAME=driftline \
        -e USER_PASSWORD="$PASSWORD" \
        -e PUBLIC_KEY="$(cat "$KEY_PATH.pub")" \
        lscr.io/linuxserver/openssh-server:latest >/dev/null
    else
      docker run -d --name "$NAME" \
        -p "$PORT:2222" \
        -e SUDO_ACCESS=false \
        -e PASSWORD_ACCESS=false \
        -e USER_NAME=driftline \
        -e PUBLIC_KEY="$(cat "$KEY_PATH.pub")" \
        lscr.io/linuxserver/openssh-server:latest >/dev/null
    fi
    echo "Started $NAME on port $PORT"
    echo "Export:"
    echo "  export DRIFTLINE_INTEGRATION_SFTP=1"
    echo "  export DRIFTLINE_TEST_HOST=127.0.0.1"
    echo "  export DRIFTLINE_TEST_PORT=$PORT"
    echo "  export DRIFTLINE_TEST_USER=driftline"
    echo "  export DRIFTLINE_TEST_KEY=$KEY_PATH"
    if [[ -n "$PASSWORD" ]]; then
      echo "  export DRIFTLINE_TEST_PASSWORD=$PASSWORD"
      echo "  export DRIFTLINE_NATIVE_INTEGRATION_SFTP=1"
    fi
    ;;
  stop)
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    echo "Stopped $NAME"
    ;;
  *)
    echo "usage: $0 [start|stop]" >&2
    exit 2
    ;;
esac
