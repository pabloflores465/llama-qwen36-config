#!/usr/bin/env bash
# Start one persistent llama.cpp router and generate presets from config/*.conf.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODELS_DIR="$ROOT_DIR/models"; CONFIG_DIR="$ROOT_DIR/config"
RUN_DIR="$MODELS_DIR/.run"; LOG_DIR="$ROOT_DIR/logs"
PI_SETTINGS="$ROOT_DIR/.pi/settings.json"
PID_FILE="$RUN_DIR/server.pid"; STATE_FILE="$RUN_DIR/server.state"
PRESET_FILE="$RUN_DIR/router-models.ini"
MCP_PID_FILE="$RUN_DIR/searxng-mcp.pid"
MCP_LOG_FILE="${MCP_LOG_FILE:-$LOG_DIR/searxng-mcp.log}"
MCP_SCRIPT="$SCRIPT_DIR/searxng-mcp.mjs"
WEBUI_CONFIG="${WEBUI_CONFIG:-$CONFIG_DIR/webui.json}"
WEBUI_BUILTIN_TOOLS="${WEBUI_BUILTIN_TOOLS-read_file,file_glob_search,grep_search,exec_shell_command,write_file,edit_file,apply_diff}"
SEARXNG_MCP_ENABLED="${SEARXNG_MCP_ENABLED:-1}"
SEARXNG_MCP_HOST="${SEARXNG_MCP_HOST:-127.0.0.1}"
SEARXNG_MCP_PORT="${SEARXNG_MCP_PORT:-8765}"
SEARXNG_MCP_URL="http://$SEARXNG_MCP_HOST:$SEARXNG_MCP_PORT"
# shellcheck source=server/lib.sh
source "$SCRIPT_DIR/lib.sh"
mkdir -p "$RUN_DIR" "$LOG_DIR"
HOST="${HOST:-127.0.0.1}"; PORT="${1:-${PORT:-8081}}"; URL="http://$HOST:$PORT"
LOG_FILE="${LOG_FILE:-$LOG_DIR/router.log}"; HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-30}"

if [[ "${ROUTER_GENERATE_ONLY:-0}" != 1 ]]; then
  if server_matches_state "$STATE_FILE"; then
    [[ "$(state_value mode "$STATE_FILE")" == router ]] && { echo "Router already running at $URL."; exit 0; }
    echo "A single-model server is running. Stop it once with ./server/stop.sh before starting the router." >&2; exit 1
  fi
  rm -f "$PID_FILE" "$STATE_FILE"
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 && { echo "Port $PORT is occupied." >&2; exit 1; }
  command -v llama-server >/dev/null || { echo "llama-server is not in PATH." >&2; exit 1; }
fi

emit_args() {
  while (( $# > 0 )); do
    local key="$1" value=true; shift
    if [[ "$key" == --no-* ]]; then key="${key#--no-}"; value=false
    else key="${key#--}"; if (( $# > 0 )) && [[ "$1" != --* ]]; then value="$1"; shift; fi
    fi
    printf '%s = %s\n' "$key" "$value"
  done
}

tmp="$PRESET_FILE.tmp.$$"; : >"$tmp"
for conf in "$CONFIG_DIR"/*.conf; do
  (
    export MODELS_DIR
    # shellcheck source=/dev/null
    source "$conf"
    [[ -f "$MODEL_PATH" ]] || { echo "Skipping $MODEL_KEY: model not found." >&2; exit 0; }
    pre_launch
    extra=(); while IFS= read -r arg; do [[ -n "$arg" ]] && extra+=("$arg"); done < <(build_extra_args)
    spec=(); while IFS= read -r arg; do [[ -n "$arg" ]] && spec+=("$arg"); done < <(build_spec_args)
    printf '[%s]\nmodel = %s\nalias = %s\nload-on-startup = false\n' "$MODEL_KEY" "$MODEL_PATH" "$ALIAS"
    emit_args --ctx-size "$CTX_SIZE" --parallel "$PARALLEL" --kv-unified \
      --threads "$THREADS" --threads-batch "$THREADS_BATCH" --batch-size "$BATCH_SIZE" \
      --ubatch-size "$UBATCH_SIZE" --n-gpu-layers "$N_GPU_LAYERS" \
      --cache-type-k "$CACHE_TYPE_K" --cache-type-v "$CACHE_TYPE_V" \
      --flash-attn "$FLASH_ATTN" --split-mode layer --cache-ram "$CACHE_RAM"
    [[ "$ENABLE_MMPROJ" == 1 ]] && emit_args --mmproj "$MMPROJ_PATH"
    [[ "$ENABLE_MMPROJ" == 1 && -n "${IMAGE_MIN_TOKENS:-}" ]] && emit_args --image-min-tokens "$IMAGE_MIN_TOKENS"
    if [[ "$KV_OFFLOAD" == 1 ]]; then emit_args --kv-offload; else emit_args --no-kv-offload; fi
    if [[ "$OP_OFFLOAD" == 1 ]]; then emit_args --op-offload; else emit_args --no-op-offload; fi
    (( ${#extra[@]} > 0 )) && emit_args "${extra[@]}"
    (( ${#spec[@]} > 0 )) && emit_args "${spec[@]}"
    printf '\n'
  ) >>"$tmp"
done
mv "$tmp" "$PRESET_FILE"
if [[ "${ROUTER_GENERATE_ONLY:-0}" == 1 ]]; then
  echo "Generated router preset: $PRESET_FILE"
  exit 0
fi

MCP_PID=""
MCP_OWNED=0
if [[ "$SEARXNG_MCP_ENABLED" == 1 ]]; then
  command -v node >/dev/null || { echo "node is required for the SearXNG MCP bridge." >&2; exit 1; }
  [[ -f "$MCP_SCRIPT" ]] || { echo "SearXNG MCP bridge not found: $MCP_SCRIPT" >&2; exit 1; }
  [[ -f "$WEBUI_CONFIG" ]] || { echo "Web UI config not found: $WEBUI_CONFIG" >&2; exit 1; }
  if ! curl -fsS --max-time 2 "$SEARXNG_MCP_URL/health" >/dev/null 2>&1; then
    SEARXNG_MCP_HOST="$SEARXNG_MCP_HOST" SEARXNG_MCP_PORT="$SEARXNG_MCP_PORT" \
      SEARXNG_URL="${SEARXNG_URL:-http://127.0.0.1:8080}" \
      nohup node "$MCP_SCRIPT" >"$MCP_LOG_FILE" 2>&1 & MCP_PID=$!
    MCP_OWNED=1
    echo "$MCP_PID" >"$MCP_PID_FILE"
    for _ in {1..30}; do
      curl -fsS --max-time 1 "$SEARXNG_MCP_URL/health" >/dev/null 2>&1 && break
      kill -0 "$MCP_PID" 2>/dev/null || { tail -20 "$MCP_LOG_FILE" >&2 || true; exit 1; }
      sleep 0.2
    done
    curl -fsS --max-time 2 "$SEARXNG_MCP_URL/health" >/dev/null || {
      echo "SearXNG MCP bridge did not become healthy." >&2
      kill "$MCP_PID" 2>/dev/null || true
      rm -f "$MCP_PID_FILE"
      exit 1
    }
  fi
fi

CMD=(llama-server --models-preset "$PRESET_FILE" --models-max 1 --models-autoload --host "$HOST" --port "$PORT")
[[ "$SEARXNG_MCP_ENABLED" == 1 ]] && CMD+=(--ui-config-file "$WEBUI_CONFIG")
[[ -n "$WEBUI_BUILTIN_TOOLS" ]] && CMD+=(--tools "$WEBUI_BUILTIN_TOOLS")
{ printf '%q ' "${CMD[@]}"; printf '\n'; } >"$LOG_FILE"
nohup "${CMD[@]}" >>"$LOG_FILE" 2>&1 & PID=$!; echo "$PID" >"$PID_FILE"
cleanup() {
  kill "$PID" 2>/dev/null || true
  [[ "$MCP_OWNED" == 1 && -n "$MCP_PID" ]] && kill "$MCP_PID" 2>/dev/null || true
  rm -f "$PID_FILE" "$STATE_FILE" "$MCP_PID_FILE"
}
deadline=$((SECONDS + HEALTH_TIMEOUT))
while (( SECONDS < deadline )); do
  valid_pid "$PID" || { tail -30 "$LOG_FILE" >&2 || true; cleanup; exit 1; }
  curl -fsS --max-time 2 "$URL/health" >/dev/null 2>&1 && break; sleep 1
done
curl -fsS --max-time 2 "$URL/health" >/dev/null || { echo "Router did not become healthy." >&2; cleanup; exit 1; }
state_tmp="$STATE_FILE.tmp.$$"
{ echo "state_version=2"; echo "mode=router"; echo "model="; echo "label=llama.cpp router"; echo "alias="
  echo "host=$HOST"; echo "port=$PORT"; echo "url=$URL"; echo "pid=$PID"; echo "log=$LOG_FILE"
  echo "preset=$PRESET_FILE"; echo "mcp_url=$SEARXNG_MCP_URL/mcp"; echo "mcp_pid=$MCP_PID"
  echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } >"$state_tmp"
mv "$state_tmp" "$STATE_FILE"; set_pi_urls "$PI_SETTINGS" "$URL"
echo "Started llama.cpp router at $URL (PID $PID)"
echo "Swap model: ./server/model_swap.sh <model-key>"
