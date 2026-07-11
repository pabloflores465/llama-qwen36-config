#!/usr/bin/env bash
# Backward-compatible name; validates that Gemma 4 12B is running.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPECTED_FAMILY=gemma4-12b exec "$SCRIPT_DIR/bench.sh" "$@"
