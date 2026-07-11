#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
bash -n server/*.sh bench/*.sh scripts/*.sh tests/*.sh config/*.conf
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is required (macOS: brew install shellcheck)." >&2
  exit 127
fi
shellcheck -x server/*.sh bench/*.sh scripts/*.sh tests/*.sh
