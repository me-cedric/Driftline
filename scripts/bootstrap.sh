#!/usr/bin/env bash
set -euo pipefail

echo "Driftline bootstrap"
echo "- Checking Swift toolchain"
swift --version
echo "- No third-party dependencies to install"
