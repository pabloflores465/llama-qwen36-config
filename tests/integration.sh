#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
cleanup() {
  [[ -f "$tmp/repo/models/.run/server.pid" ]] && "$tmp/repo/server/stop.sh" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/repo" "$tmp/bin" "$tmp/repo/models"
cp -R "$ROOT_DIR/server" "$ROOT_DIR/config" "$tmp/repo/"
ln -s "$ROOT_DIR/tests/fake-llama-server.py" "$tmp/bin/llama-server"
touch "$tmp/model.gguf"

PATH="$tmp/bin:$PATH" MODEL_PATH="$tmp/model.gguf" ENABLE_MMPROJ=0 SPEC_MODE=none \
  PORT_DEFAULT=18084 HEALTH_TIMEOUT=5 "$tmp/repo/server/start.sh" qwen35-4b >/dev/null
state="$tmp/repo/models/.run/server.state"
[[ "$(sed -n 's/^port=//p' "$state")" == 18084 ]]
[[ "$(sed -n 's/^model=//p' "$state")" == qwen35-4b ]]
curl -fsS http://127.0.0.1:18084/health >/dev/null
PATH="$tmp/bin:$PATH" "$tmp/repo/server/stop.sh" >/dev/null
[[ ! -e "$state" && ! -e "$tmp/repo/models/.run/server.pid" ]]

PATH="$tmp/bin:$PATH" MODEL_PATH="$tmp/model.gguf" ENABLE_MMPROJ=0 SPEC_MODE=none \
  HEALTH_TIMEOUT=5 MIN_FREE_PCT=0 SEARXNG_MCP_ENABLED=0 \
  "$tmp/repo/server/router.sh" 18084 >/dev/null
[[ "$(sed -n 's/^mode=//p' "$state")" == router ]]
PATH="$tmp/bin:$PATH" MODEL_PATH="$tmp/model.gguf" ENABLE_MMPROJ=0 SPEC_MODE=none \
  PI_GLOBAL_SETTINGS="$tmp/global-settings.json" "$tmp/repo/server/model_swap.sh" gemma4-e4b >/dev/null
[[ "$(sed -n 's/^model=//p' "$state")" == gemma4-e4b ]]
[[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["defaultModel"])' "$tmp/global-settings.json")" == gemma4-e4b ]]
PATH="$tmp/bin:$PATH" MODEL_PATH="$tmp/model.gguf" ENABLE_MMPROJ=0 SPEC_MODE=none \
  PI_GLOBAL_SETTINGS="$tmp/global-settings.json" "$tmp/repo/server/model_swap.sh" qwen35-4b >/dev/null
[[ "$(sed -n 's/^model=//p' "$state")" == qwen35-4b ]]
PATH="$tmp/bin:$PATH" "$tmp/repo/server/stop.sh" >/dev/null
echo "Integration lifecycle passed."
