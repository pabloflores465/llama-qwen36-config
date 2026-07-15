#!/usr/bin/env bash
# Stop only the llama-server instance that matches the recorded PID and port.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_DIR="$ROOT_DIR/models/.run"
CONFIG_DIR="$ROOT_DIR/config"
PI_SETTINGS="$ROOT_DIR/.pi/settings.json"
PID_FILE="$RUN_DIR/server.pid"
STATE_FILE="$RUN_DIR/server.state"
MCP_PID_FILE="$RUN_DIR/searxng-mcp.pid"
# shellcheck source=server/lib.sh
source "$SCRIPT_DIR/lib.sh"

PID="$(state_value pid "$STATE_FILE")"
PORT="$(state_value port "$STATE_FILE")"
MCP_PID="$(state_value mcp_pid "$STATE_FILE")"
if [[ -z "$MCP_PID" && -f "$MCP_PID_FILE" ]]; then
  MCP_PID="$(head -1 "$MCP_PID_FILE")"
fi
STOPPED=0
STOP_ATTEMPTS=30
[[ "$(state_value mode "$STATE_FILE")" == router ]] && STOP_ATTEMPTS=150

if [[ -n "$PID" ]] && is_llama_server_pid "$PID"; then
  if [[ -n "$PORT" ]] && ! pid_listens_on_port "$PID" "$PORT"; then
    echo "Refusing to stop PID $PID: it does not own recorded port $PORT." >&2
    exit 1
  fi
  echo "Stopping llama-server PID $PID ..."
  kill "$PID"
  for (( attempt = 0; attempt < STOP_ATTEMPTS; attempt++ )); do
    valid_pid "$PID" || { STOPPED=1; break; }
    sleep 0.2
  done
  if valid_pid "$PID"; then
    echo "llama-server did not stop gracefully; sending KILL."
    kill -9 "$PID" 2>/dev/null || true
  fi
  STOPPED=1
elif [[ -n "$PID" ]]; then
  echo "Recorded PID $PID is stale or is not llama-server; leaving the process untouched."
fi

rm -f "$PID_FILE" "$STATE_FILE"
set_pi_urls "$PI_SETTINGS" "$(default_pi_urls "$CONFIG_DIR")"
[[ "$STOPPED" == 1 ]] && echo "llama-server stopped." || echo "Stale state cleaned; no running llama-server found."

if [[ "$MCP_PID" =~ ^[0-9]+$ ]] && valid_pid "$MCP_PID"; then
  MCP_COMMAND="$(ps -p "$MCP_PID" -o command= 2>/dev/null || true)"
  if [[ "$MCP_COMMAND" == *searxng-mcp.mjs* ]]; then
    echo "Stopping SearXNG MCP bridge PID $MCP_PID ..."
    kill "$MCP_PID" 2>/dev/null || true
  fi
fi
rm -f "$MCP_PID_FILE"
