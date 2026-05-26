#!/usr/bin/env bash
set -euo pipefail

echo "SwiftFormat/SwiftLint are not yet pinned. Running compiler checks instead."
swift build
