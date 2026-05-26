#!/usr/bin/env bash
set -euo pipefail

git log --oneline "$(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~20)"..HEAD
