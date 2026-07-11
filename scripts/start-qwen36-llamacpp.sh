#!/usr/bin/env bash
# Compatibility entry point retained after the config-driven migration.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/../server/start.sh" qwen36-35b "${PORT:-8081}"
