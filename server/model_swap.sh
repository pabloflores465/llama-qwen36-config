#!/usr/bin/env bash
# Switch the active model on a llama.cpp router without restarting the router.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
RUN_DIR="$ROOT_DIR/models/.run"
STATE_FILE="$RUN_DIR/server.state"
PI_PROJECT_SETTINGS="$ROOT_DIR/.pi/settings.json"
PI_GLOBAL_SETTINGS="${PI_GLOBAL_SETTINGS:-$HOME/.pi/agent/settings.json}"
# shellcheck source=server/lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  echo "Usage: ./server/model_swap.sh <model-key>" >&2
  echo "Available model keys:" >&2
  find "$CONFIG_DIR" -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null |
    sed 's#.*/##; s#\.conf$##' | sort | sed 's/^/  /' >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
MODEL_KEY="$1"
CONF="$CONFIG_DIR/$MODEL_KEY.conf"
[[ -f "$CONF" ]] || { echo "No config for '$MODEL_KEY'." >&2; usage; }

URL="${LLAMA_ROUTER_URL:-$(state_value url "$STATE_FILE")}"
[[ -n "$URL" ]] || { echo "No running router state found. Set LLAMA_ROUTER_URL or start the router first." >&2; exit 1; }
curl -fsS --max-time 2 "$URL/health" >/dev/null || { echo "Router is not healthy at $URL." >&2; exit 1; }

# Router preset sections use the profile key as their model ID. Validate the
# profile now so callers cannot swap to a removed/broken configuration.
export MODELS_DIR="$ROOT_DIR/models"
# shellcheck source=/dev/null
source "$CONF"
[[ -f "$MODEL_PATH" ]] || { echo "Model not found: $MODEL_PATH" >&2; exit 1; }

record_active_model() {
  local state_tmp="$STATE_FILE.tmp.$$"
  awk -v model="$MODEL_KEY" -v label="$MODEL_LABEL" -v alias="$ALIAS" '
    /^model=/ { print "model=" model; next }
    /^label=/ { print "label=" label; next }
    /^alias=/ { print "alias=" alias; next }
    { print }
  ' "$STATE_FILE" >"$state_tmp"
  mv "$state_tmp" "$STATE_FILE"
  set_pi_model "$PI_PROJECT_SETTINGS" "$MODEL_KEY"
  set_pi_model "$PI_GLOBAL_SETTINGS" "$MODEL_KEY"
}

models_json="$(curl -fsS --max-time 5 "$URL/models")" || {
  echo "The endpoint did not expose /models. Start llama-server in router mode (--models-preset …)." >&2
  exit 1
}

if ! python3 -c '
import json, sys
raise SystemExit(0 if any(x.get("id") == sys.argv[1] for x in json.load(sys.stdin).get("data", [])) else 1)
' "$MODEL_KEY" <<<"$models_json"; then
  echo "Model '$MODEL_KEY' is not registered. Restart once with ./server/router.sh to regenerate presets." >&2
  exit 1
fi

target_status="$(python3 -c '
import json, sys
for item in json.load(sys.stdin).get("data", []):
    if item.get("id") == sys.argv[1]:
        print(item.get("status", {}).get("value", ""))
        break
' "$MODEL_KEY" <<<"$models_json")"
if [[ "$target_status" == loaded || "$target_status" == loading || "$target_status" == sleeping ]]; then
  record_active_model
  echo "Model already $target_status: $MODEL_KEY ($MODEL_LABEL) at $URL"
  exit 0
fi

loaded=()
while IFS= read -r current; do
  [[ -n "$current" ]] && loaded+=("$current")
done < <(python3 -c '
import json, sys
for item in json.load(sys.stdin).get("data", []):
    if item.get("status", {}).get("value") in {"loaded", "loading", "sleeping"}:
        print(item["id"])
' <<<"$models_json")

if (( ${#loaded[@]} > 0 )); then
  for current in "${loaded[@]}"; do
    [[ "$current" == "$MODEL_KEY" ]] && continue
    echo "Unloading $current …"
    curl --fail-with-body -sS --max-time 30 -X POST "$URL/models/unload" \
      -H 'Content-Type: application/json' \
      --data "$(python3 -c 'import json,sys; print(json.dumps({"model": sys.argv[1]}))' "$current")" >/dev/null
  done
fi

echo "Loading $MODEL_KEY …"
curl --fail-with-body -sS --max-time "${MODEL_SWAP_TIMEOUT:-240}" -X POST "$URL/models/load" \
  -H 'Content-Type: application/json' \
  --data "$(python3 -c 'import json,sys; print(json.dumps({"model": sys.argv[1]}))' "$MODEL_KEY")" >/dev/null

record_active_model

echo "Model swap requested: $MODEL_KEY ($MODEL_LABEL) at $URL"
