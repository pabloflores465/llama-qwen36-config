#!/usr/bin/env bash
# Reproducible benchmark for the single server described by server.state.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$ROOT_DIR/models/.run/server.state"
PID_FILE="$ROOT_DIR/models/.run/server.pid"
CONFIG_DIR="$ROOT_DIR/config"
PI_SETTINGS="$ROOT_DIR/.pi/settings.json"
# shellcheck source=server/lib.sh
source "$ROOT_DIR/server/lib.sh"

[[ -f "$STATE_FILE" ]] || { echo "No server state. Start a server first." >&2; exit 1; }
if ! server_matches_state "$STATE_FILE"; then
  rm -f "$STATE_FILE" "$PID_FILE"
  set_pi_urls "$PI_SETTINGS" "$(default_pi_urls "$CONFIG_DIR")" 2>/dev/null || true
  echo "Recorded server was stale; runtime state was repaired." >&2
  exit 1
fi

MODEL="$(state_value model "$STATE_FILE")"
ALIAS="$(state_value alias "$STATE_FILE")"
URL="${URL:-$(state_value url "$STATE_FILE")}"
EXPECTED_FAMILY="${EXPECTED_FAMILY:-}"
if [[ -n "$EXPECTED_FAMILY" && "$MODEL" != "$EXPECTED_FAMILY"* ]]; then
  echo "Expected a $EXPECTED_FAMILY model, but $MODEL is running." >&2; exit 1
fi

API_MODELS="$(curl -fsS "$URL/v1/models")"
python3 - "$API_MODELS" "$ALIAS" <<'PY'
import json, sys
models, expected = json.loads(sys.argv[1]), sys.argv[2]
ids = [str(x.get("id", "")) for x in models.get("data", [])]
if expected not in ids:
    raise SystemExit(f"Running API models {ids!r} do not contain recorded alias {expected!r}")
PY

OUT="${OUT:-$ROOT_DIR/logs/${MODEL}-bench.jsonl}"
MATRIX="${MATRIX:-2048:128 16384:64 65536:32}"
mkdir -p "$(dirname "$OUT")"

for item in $MATRIX; do
  [[ "$item" =~ ^[0-9]+:[0-9]+$ ]] || { echo "Invalid MATRIX item: $item" >&2; exit 2; }
  target="${item%:*}"; gen="${item#*:}"
  python3 - "$URL" "$STATE_FILE" "$target" "$gen" >>"$OUT" <<'PY'
import json, platform, sys, time, urllib.request
url, state_path, target, gen = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
state = {}
with open(state_path, encoding="utf-8") as f:
    for line in f:
        key, sep, value = line.rstrip("\n").partition("=")
        if sep: state[key] = value
def post(path, obj):
    req = urllib.request.Request(url + path, json.dumps(obj).encode(), {"Content-Type":"application/json"})
    with urllib.request.urlopen(req, timeout=3600) as response:
        return json.loads(response.read())
unit = "alpha beta gamma delta epsilon zeta eta theta. "
sample = unit * max(1, target // 6)
for _ in range(3):
    count = len(post("/tokenize", {"content": sample}).get("tokens", []))
    if not count: raise RuntimeError("/tokenize returned no tokens")
    sample = sample[:max(1, round(len(sample) * target / count))]
actual = len(post("/tokenize", {"content": sample}).get("tokens", []))
payload = {"prompt": sample, "n_predict": gen, "temperature": 0, "seed": 42,
           "ignore_eos": True, "cache_prompt": False}
started = time.time(); data = post("/completion", payload); wall = time.time() - started
timings = data.get("timings", {})
row = {"type":"benchmark", "timestamp":time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
       "model":state.get("model"), "alias":state.get("alias"), "url":url,
       "target_prompt":target, "tokenized_prompt":actual, "requested_gen":gen,
       "prompt_n":timings.get("prompt_n"), "prompt_tok_s":timings.get("prompt_per_second"),
       "gen_n":timings.get("predicted_n"), "gen_tok_s":timings.get("predicted_per_second"),
       "prompt_ms":timings.get("prompt_ms"), "gen_ms":timings.get("predicted_ms"),
       "wall_s":round(wall, 3), "platform":platform.platform()}
for key in ("spec_mode","ctx_size","batch_size","ubatch_size","threads","threads_batch",
            "parallel","cache_type_k","cache_type_v","kv_offload","op_offload",
            "n_gpu_layers","mmproj","started"):
    row[key] = state.get(key)
print(json.dumps(row, separators=(",", ":")), flush=True)
PY
  pid="$(state_value pid "$STATE_FILE")"
  ps -o pid=,rss=,vsz=,%cpu= -p "$pid" 2>/dev/null |
    awk -v m="$MODEL" -v p="$target" '{printf "{\"type\":\"memory\",\"model\":\"%s\",\"after_prompt\":%s,\"pid\":%s,\"rss_kib\":%s,\"vsz_kib\":%s,\"cpu_pct\":%s}\n",m,p,$1,$2,$3,$4}' >>"$OUT" || true
done
echo "Wrote $OUT"
