#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="${PID_FILE:-$ROOT_DIR/llama-server.pid}"
PORT="${PORT:-8081}"

stop_pid() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    return 1
  fi

  if ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi

  echo "Stopping llama-server PID $pid ..."
  kill "$pid" 2>/dev/null || true

  for _ in {1..30}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "Stopped."
      return 0
    fi
    sleep 0.5
  done

  echo "PID $pid did not exit; force killing ..."
  kill -9 "$pid" 2>/dev/null || true
  echo "Stopped."
}

STOPPED=0

if [[ -f "$PID_FILE" ]]; then
  PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if stop_pid "$PID"; then
    STOPPED=1
  else
    echo "PID file exists but process is not running: $PID_FILE"
  fi
  rm -f "$PID_FILE"
fi

# Also stop any llama-server listening on the configured port, in case the PID file is stale.
PIDS_ON_PORT="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
if [[ -n "$PIDS_ON_PORT" ]]; then
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    if stop_pid "$pid"; then
      STOPPED=1
    fi
  done <<< "$PIDS_ON_PORT"
fi

# Last-resort cleanup for this specific model/server command.
LEFTOVER="$(pgrep -f 'llama-server.*Qwen3.6-35B' 2>/dev/null || true)"
if [[ -n "$LEFTOVER" ]]; then
  echo "Stopping leftover Qwen3.6 llama-server processes ..."
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    if stop_pid "$pid"; then
      STOPPED=1
    fi
  done <<< "$LEFTOVER"
fi

if [[ "$STOPPED" == "0" ]]; then
  echo "No llama-server process found."
else
  echo "llama-server stopped."
fi
