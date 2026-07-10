#!/usr/bin/env bash
set -euo pipefail

# Qwen3.6-35B-A3B-MTP llama.cpp server tuned for Apple Silicon / Metal.
# Model native/full context is 262144 tokens (from GGUF metadata), but default is 32K for now.
# llama.cpp currently exposes q4_0/q4_1/iq4_nl/q5_* KV cache types, not q3,
# so V uses q4_0 as the closest supported low-memory setting.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_PATH="${MODEL_PATH:-$ROOT_DIR/models/Qwen3.6-35B-A3B-MTP-GGUF/Qwen3.6-35B-A3B-UD-IQ2_M.gguf}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8081}"

# Loading profiles. On 16 GB Apple Silicon, large Metal allocations can starve
# WindowServer and cause display flicker. The default profile uses full context
# with CPU/RAM execution and quantized KV cache for stability.
PROFILE="${PROFILE:-auto}"
TOTAL_MEM_GB=$(( ( $(sysctl -n hw.memsize) + 1073741823 ) / 1073741824 ))
if [[ "$PROFILE" == "auto" ]]; then
  if (( TOTAL_MEM_GB <= 18 )); then
    PROFILE="fullctx16"
  else
    PROFILE="balanced"
  fi
fi

case "$PROFILE" in
  fullctx16)
    DEFAULT_CTX_SIZE=262144
    DEFAULT_THREADS=8
    DEFAULT_BATCH_SIZE=2048
    DEFAULT_UBATCH_SIZE=2048
    DEFAULT_N_GPU_LAYERS=0
    DEFAULT_KV_OFFLOAD=0
    DEFAULT_OP_OFFLOAD=0
    DEFAULT_FLASH_ATTN=on
    ;;
  safe16)
    DEFAULT_CTX_SIZE=8192
    DEFAULT_BATCH_SIZE=128
    DEFAULT_UBATCH_SIZE=64
    DEFAULT_N_GPU_LAYERS=8
    DEFAULT_KV_OFFLOAD=0
    DEFAULT_OP_OFFLOAD=1
    DEFAULT_FLASH_ATTN=auto
    ;;
  long16)
    DEFAULT_CTX_SIZE=16384
    DEFAULT_BATCH_SIZE=128
    DEFAULT_UBATCH_SIZE=64
    DEFAULT_N_GPU_LAYERS=4
    DEFAULT_KV_OFFLOAD=0
    DEFAULT_OP_OFFLOAD=1
    DEFAULT_FLASH_ATTN=auto
    ;;
  balanced)
    DEFAULT_CTX_SIZE=16384
    DEFAULT_BATCH_SIZE=256
    DEFAULT_UBATCH_SIZE=128
    DEFAULT_N_GPU_LAYERS=16
    DEFAULT_KV_OFFLOAD=1
    DEFAULT_OP_OFFLOAD=1
    DEFAULT_FLASH_ATTN=auto
    ;;
  risky32k)
    DEFAULT_CTX_SIZE=32768
    DEFAULT_BATCH_SIZE=512
    DEFAULT_UBATCH_SIZE=128
    DEFAULT_N_GPU_LAYERS=24
    DEFAULT_KV_OFFLOAD=1
    DEFAULT_OP_OFFLOAD=1
    DEFAULT_FLASH_ATTN=on
    ;;
  custom)
    DEFAULT_CTX_SIZE=8192
    DEFAULT_BATCH_SIZE=128
    DEFAULT_UBATCH_SIZE=64
    DEFAULT_N_GPU_LAYERS=8
    DEFAULT_KV_OFFLOAD=0
    DEFAULT_OP_OFFLOAD=1
    DEFAULT_FLASH_ATTN=auto
    ;;
  *)
    echo "Unknown PROFILE=$PROFILE. Use auto, fullctx16, safe16, long16, balanced, risky32k, or custom." >&2
    exit 1
    ;;
esac

DEFAULT_THREADS="${DEFAULT_THREADS:-$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || sysctl -n hw.ncpu)}"
CTX_SIZE="${CTX_SIZE:-$DEFAULT_CTX_SIZE}"
THREADS="${THREADS:-$DEFAULT_THREADS}"
BATCH_SIZE="${BATCH_SIZE:-$DEFAULT_BATCH_SIZE}"
UBATCH_SIZE="${UBATCH_SIZE:-$DEFAULT_UBATCH_SIZE}"
CACHE_TYPE_K="${CACHE_TYPE_K:-q4_0}"
CACHE_TYPE_V="${CACHE_TYPE_V:-q4_0}"
N_GPU_LAYERS="${N_GPU_LAYERS:-$DEFAULT_N_GPU_LAYERS}"
KV_OFFLOAD="${KV_OFFLOAD:-$DEFAULT_KV_OFFLOAD}"
OP_OFFLOAD="${OP_OFFLOAD:-$DEFAULT_OP_OFFLOAD}"
FLASH_ATTN="${FLASH_ATTN:-$DEFAULT_FLASH_ATTN}"
ENABLE_MTP="${ENABLE_MTP:-0}"
DRAFT_N_MAX="${DRAFT_N_MAX:-2}"
DRAFT_N_MIN="${DRAFT_N_MIN:-1}"
PARALLEL="${PARALLEL:-1}"
NICE_LEVEL="${NICE_LEVEL:-10}"
MEMORY_GUARD="${MEMORY_GUARD:-1}"
MIN_FREE_PCT="${MIN_FREE_PCT:-20}"
ALIAS="${ALIAS:-Qwen3.6-35B-A3B-MTP-IQ2_M}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
PID_FILE="${PID_FILE:-$ROOT_DIR/llama-server.pid}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/qwen36-llamacpp.log}"

mkdir -p "$LOG_DIR"

if [[ ! -f "$MODEL_PATH" ]]; then
  echo "Model not found: $MODEL_PATH" >&2
  exit 1
fi

if [[ "$MEMORY_GUARD" == "1" ]] && command -v memory_pressure >/dev/null 2>&1; then
  FREE_PCT="$(memory_pressure | awk '/System-wide memory free percentage/ { gsub(/%/, "", $5); print $5 }')"
  if [[ "$FREE_PCT" =~ ^[0-9]+$ ]] && (( FREE_PCT < MIN_FREE_PCT )); then
    echo "Memory guard: only ${FREE_PCT}% reported free; refusing to start to avoid display flicker/swap." >&2
    echo "Close apps or retry with MEMORY_GUARD=0 if you know what you are doing." >&2
    exit 1
  fi
fi

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "llama-server already running with PID $(cat "$PID_FILE")"
  echo "URL: http://$HOST:$PORT"
  exit 0
fi

# Refuse to collide with another process on this port.
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is already in use:" >&2
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2 || true
  exit 1
fi

CMD=(
  llama-server
  --model "$MODEL_PATH"
  --alias "$ALIAS"
  --host "$HOST"
  --port "$PORT"
  --ctx-size "$CTX_SIZE"
  --threads "$THREADS"
  --threads-batch "$THREADS"
  --batch-size "$BATCH_SIZE"
  --ubatch-size "$UBATCH_SIZE"
  --parallel "$PARALLEL"
  --cache-type-k "$CACHE_TYPE_K"
  --cache-type-v "$CACHE_TYPE_V"
  --flash-attn "$FLASH_ATTN"
  --cpu-moe
  --n-gpu-layers "$N_GPU_LAYERS"
  --split-mode layer
  --cont-batching
  --jinja
  --reasoning auto
  --reasoning-format deepseek
  --no-warmup
  --metrics
  --slots
)

if [[ "$KV_OFFLOAD" == "1" ]]; then
  CMD+=(--kv-offload)
else
  CMD+=(--no-kv-offload)
fi

if [[ "$OP_OFFLOAD" == "1" ]]; then
  CMD+=(--op-offload)
else
  CMD+=(--no-op-offload)
fi

if [[ "$ENABLE_MTP" == "1" ]]; then
  CMD+=(
    --spec-type draft-mtp
    --spec-draft-n-max "$DRAFT_N_MAX"
    --spec-draft-n-min "$DRAFT_N_MIN"
  )
fi

{
  echo "Starting llama-server:"
  echo "  profile=$PROFILE total_mem_gb=$TOTAL_MEM_GB nice=$NICE_LEVEL"
  echo "  ctx=$CTX_SIZE batch=$BATCH_SIZE ubatch=$UBATCH_SIZE ngl=$N_GPU_LAYERS kv_offload=$KV_OFFLOAD op_offload=$OP_OFFLOAD flash_attn=$FLASH_ATTN cache=$CACHE_TYPE_K/$CACHE_TYPE_V"
  printf '  %q' "${CMD[@]}"
  printf '\n\n'
} > "$LOG_FILE"
nohup nice -n "$NICE_LEVEL" "${CMD[@]}" >> "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

echo "Started llama-server PID $(cat "$PID_FILE")"
echo "URL: http://$HOST:$PORT"
echo "Log: $LOG_FILE"
