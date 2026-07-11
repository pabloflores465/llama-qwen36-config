#!/usr/bin/env bash
# Start one config-driven llama-server and publish state only after /health passes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODELS_DIR="$ROOT_DIR/models"
CONFIG_DIR="$ROOT_DIR/config"
RUN_DIR="$MODELS_DIR/.run"
LOG_DIR="$ROOT_DIR/logs"
PI_SETTINGS="$ROOT_DIR/.pi/settings.json"
PID_FILE="$RUN_DIR/server.pid"
STATE_FILE="$RUN_DIR/server.state"
# shellcheck source=server/lib.sh
source "$SCRIPT_DIR/lib.sh"

mkdir -p "$RUN_DIR" "$LOG_DIR"
DEFAULT_MODEL_KEY="gemma4-12b"

list_configs() {
  find "$CONFIG_DIR" -maxdepth 1 -name '*.conf' -type f -print 2>/dev/null |
    sed 's#.*/##; s#\.conf$##' | sort
}

MODEL_KEY="${1:-}"
if [[ -z "$MODEL_KEY" ]]; then
  echo "Available models:"
  while IFS= read -r name; do
    label="$(sed -n 's/^MODEL_LABEL="\(.*\)"$/\1/p' "$CONFIG_DIR/$name.conf")"
    echo "  $name    ${label:+— $label}"
  done < <(list_configs)
  echo
  read -rp "Model [default: $DEFAULT_MODEL_KEY]: " MODEL_KEY
  MODEL_KEY="${MODEL_KEY:-$DEFAULT_MODEL_KEY}"
fi

CONF="$CONFIG_DIR/$MODEL_KEY.conf"
[[ -f "$CONF" ]] || { echo "No config for '$MODEL_KEY' ($CONF)." >&2; exit 1; }
export MODELS_DIR
# shellcheck source=/dev/null
source "$CONF"

# The model config must be loaded before selecting its default port.
PORT="${2:-${PORT:-}}"
if [[ -z "$PORT" ]]; then
  if [[ -t 0 ]]; then
    read -rp "Port [default: $PORT_DEFAULT]: " PORT
  fi
  PORT="${PORT:-$PORT_DEFAULT}"
fi
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "Port must be between 1 and 65535 (got '$PORT')." >&2; exit 1;
fi

# Repair stale runtime metadata before deciding whether another server exists.
if [[ -f "$PID_FILE" || -f "$STATE_FILE" ]]; then
  if server_matches_state "$STATE_FILE"; then
    echo "A llama-server is already running (PID $(state_value pid "$STATE_FILE"))." >&2
    echo "Stop it first: ./server/stop.sh" >&2
    exit 1
  fi
  echo "Removing stale llama-server state."
  rm -f "$PID_FILE" "$STATE_FILE"
  set_pi_urls "$PI_SETTINGS" "$(default_pi_urls "$CONFIG_DIR")" 2>/dev/null || true
fi
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is already occupied:" >&2
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2 || true
  exit 1
fi

[[ -f "$MODEL_PATH" ]] || { echo "Model not found: $MODEL_PATH" >&2; exit 1; }
if [[ "$ENABLE_MMPROJ" == 1 ]]; then
  [[ -f "$MMPROJ_PATH" ]] || { echo "Multimodal projector not found: $MMPROJ_PATH" >&2; exit 1; }
fi
command -v llama-server >/dev/null || { echo "llama-server is not installed or not in PATH." >&2; exit 1; }
pre_launch

HOST="${HOST:-127.0.0.1}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/$MODEL_KEY.log}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-180}"
URL="http://$HOST:$PORT"
CMD=(llama-server --model "$MODEL_PATH" --alias "$ALIAS"
  --host "$HOST" --port "$PORT" --ctx-size "$CTX_SIZE" --parallel "$PARALLEL" --kv-unified
  --threads "$THREADS" --threads-batch "$THREADS_BATCH"
  --batch-size "$BATCH_SIZE" --ubatch-size "$UBATCH_SIZE" --n-gpu-layers "$N_GPU_LAYERS"
  --cache-type-k "$CACHE_TYPE_K" --cache-type-v "$CACHE_TYPE_V"
  --flash-attn "$FLASH_ATTN" --split-mode layer --cache-ram "$CACHE_RAM")
[[ "$ENABLE_MMPROJ" == 1 ]] && CMD+=(--mmproj "$MMPROJ_PATH")
[[ "$ENABLE_MMPROJ" == 1 && -n "${IMAGE_MIN_TOKENS:-}" ]] && CMD+=(--image-min-tokens "$IMAGE_MIN_TOKENS")
[[ "$KV_OFFLOAD" == 1 ]] && CMD+=(--kv-offload) || CMD+=(--no-kv-offload)
[[ "$OP_OFFLOAD" == 1 ]] && CMD+=(--op-offload) || CMD+=(--no-op-offload)
EXTRA_ARGS=(); while IFS= read -r arg; do [[ -n "$arg" ]] && EXTRA_ARGS+=("$arg"); done < <(build_extra_args)
SPEC_ARGS=(); while IFS= read -r arg; do [[ -n "$arg" ]] && SPEC_ARGS+=("$arg"); done < <(build_spec_args)
[[ "${#EXTRA_ARGS[@]}" -gt 0 ]] && CMD+=("${EXTRA_ARGS[@]}")
[[ "${#SPEC_ARGS[@]}" -gt 0 ]] && CMD+=("${SPEC_ARGS[@]}")

{
  echo "model=$MODEL_KEY alias=$ALIAS port=$PORT ctx=$CTX_SIZE"
  echo "spec=$SPEC_MODE mmproj=$ENABLE_MMPROJ host=$HOST"
  printf '%q ' "${CMD[@]}"; printf '\n'
} >"$LOG_FILE"

cleanup_failed_start() {
  local code="${1:-1}"
  if [[ -n "${PID:-}" ]] && is_llama_server_pid "$PID"; then kill "$PID" 2>/dev/null || true; fi
  rm -f "$PID_FILE" "$STATE_FILE"
  set_pi_urls "$PI_SETTINGS" "$(default_pi_urls "$CONFIG_DIR")" 2>/dev/null || true
  return "$code"
}

if [[ "${FOREGROUND:-0}" == 1 ]]; then
  "${CMD[@]}" >>"$LOG_FILE" 2>&1 & PID=$!
else
  nohup "${CMD[@]}" >>"$LOG_FILE" 2>&1 & PID=$!
fi
echo "$PID" >"$PID_FILE"

deadline=$((SECONDS + HEALTH_TIMEOUT))
while (( SECONDS < deadline )); do
  if ! valid_pid "$PID"; then
    echo "llama-server exited before becoming healthy. Last log lines:" >&2
    tail -30 "$LOG_FILE" >&2 || true
    cleanup_failed_start 1
    exit 1
  fi
  curl -fsS --max-time 2 "$URL/health" >/dev/null 2>&1 && break
  sleep 1
done
if ! curl -fsS --max-time 2 "$URL/health" >/dev/null 2>&1; then
  echo "llama-server did not become healthy within ${HEALTH_TIMEOUT}s." >&2
  cleanup_failed_start 1
  exit 1
fi

STATE_TMP="$STATE_FILE.tmp.$$"
{
  echo "state_version=1"; echo "model=$MODEL_KEY"; echo "label=$MODEL_LABEL"; echo "alias=$ALIAS"
  echo "host=$HOST"; echo "port=$PORT"; echo "url=$URL"; echo "pid=$PID"; echo "log=$LOG_FILE"
  echo "spec_mode=$SPEC_MODE"; echo "ctx_size=$CTX_SIZE"; echo "batch_size=$BATCH_SIZE"
  echo "ubatch_size=$UBATCH_SIZE"; echo "threads=$THREADS"; echo "threads_batch=$THREADS_BATCH"
  echo "parallel=$PARALLEL"; echo "cache_type_k=$CACHE_TYPE_K"; echo "cache_type_v=$CACHE_TYPE_V"
  echo "kv_offload=$KV_OFFLOAD"; echo "op_offload=$OP_OFFLOAD"; echo "n_gpu_layers=$N_GPU_LAYERS"
  echo "mmproj=$ENABLE_MMPROJ"; echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$STATE_TMP"
mv "$STATE_TMP" "$STATE_FILE"
set_pi_urls "$PI_SETTINGS" "$URL" || echo "Warning: could not update $PI_SETTINGS" >&2

echo "Started $MODEL_LABEL at $URL (PID $PID)"
echo "Log:   $LOG_FILE"
echo "State: $STATE_FILE"

if [[ "${FOREGROUND:-0}" == 1 ]]; then
  trap 'kill -TERM "$PID" 2>/dev/null || true' TERM
  trap 'kill -INT "$PID" 2>/dev/null || true' INT
  set +e; wait "$PID"; status=$?; set -e
  rm -f "$PID_FILE" "$STATE_FILE"
  set_pi_urls "$PI_SETTINGS" "$(default_pi_urls "$CONFIG_DIR")" 2>/dev/null || true
  exit "$status"
fi
