#!/usr/bin/env bash
# llama/server/slot.sh — save/restore/list/erase the llama-server slot
# for the single running server. Reads models/.run/server.state for the port.
#
# Usage:
#   ./server/slot.sh save NAME.bin
#   ./server/slot.sh restore NAME.bin
#   ./server/slot.sh erase
#   ./server/slot.sh list
#   ./server/slot.sh status
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODELS_DIR="$ROOT_DIR/models"
RUN_DIR="$MODELS_DIR/.run"
STATE_FILE="$RUN_DIR/server.state"
PID_FILE="$RUN_DIR/server.pid"
CONFIG_DIR="$ROOT_DIR/config"
PI_SETTINGS="$ROOT_DIR/.pi/settings.json"
# shellcheck source=server/lib.sh
source "$SCRIPT_DIR/lib.sh"

ACTION="${1:-}"
SLOT_ID="${SLOT_ID:-0}"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "No running server recorded (no $STATE_FILE). Start one first: ./server/start.sh" >&2
  exit 1
fi
if ! server_matches_state "$STATE_FILE"; then
  rm -f "$STATE_FILE" "$PID_FILE"
  set_pi_urls "$PI_SETTINGS" "$(default_pi_urls "$CONFIG_DIR")" 2>/dev/null || true
  echo "Removed stale server state; no healthy recorded llama-server is running." >&2
  exit 1
fi

URL="$(sed -n 's/^url=//p' "$STATE_FILE" | head -1)"
ALIAS="$(sed -n 's/^alias=//p' "$STATE_FILE" | head -1)"
[ -n "$URL" ] || { echo "No url in $STATE_FILE." >&2; exit 1; }

case "$ACTION" in
  save|restore)
    NAME="${2:-}"
    [ -n "$NAME" ] || { echo "Usage: $0 $ACTION NAME" >&2; exit 2; }
    PAYLOAD="$(python3 -c 'import json,sys; print(json.dumps({"filename":sys.argv[1]}))' "$NAME")"
    curl -fsS -X POST "$URL/slots/$SLOT_ID?action=$ACTION" \
      -H 'Content-Type: application/json' --data-binary "$PAYLOAD"
    echo
    ;;
  erase)
    curl -fsS -X POST "$URL/slots/$SLOT_ID?action=erase"; echo
    ;;
  list)
    curl -fsS "$URL/slots"; echo
    ;;
  status)
    curl -fsS -X GET "$URL/v1/models" 2>/dev/null | python3 -m json.tool 2>/dev/null \
      || curl -fsS "$URL/models"; echo
    echo "--- state ---"; sed 's/^/  /' "$STATE_FILE"
    ;;
  *)
    cat <<EOF
Usage: $0 {save NAME | restore NAME | erase | list | status}
Running server: $ALIAS at $URL (slot $SLOT_ID)
EOF
    exit 2
    ;;
esac
