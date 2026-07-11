#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=server/lib.sh
source "$ROOT_DIR/server/lib.sh"
failures=0

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $message: expected '$expected', got '$actual'" >&2
    failures=$((failures + 1))
  else
    echo "ok: $message"
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'pid=123\nport=8081\nmodel=test\n' >"$tmp/state"
assert_eq 123 "$(state_value pid "$tmp/state")" "state_value reads PID"
assert_eq test "$(state_value model "$tmp/state")" "state_value reads model"
assert_eq "" "$(state_value missing "$tmp/state")" "missing state value is empty"

urls="$(default_pi_urls "$ROOT_DIR/config")"
assert_eq "http://127.0.0.1:8081" "$urls" "Pi defaults to canonical port 8081"

printf '{"preserved": true}\n' >"$tmp/settings.json"
set_pi_urls "$tmp/settings.json" "http://127.0.0.1:9999"
python3 - "$tmp/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d == {"preserved": True, "llamaServerUrl": "http://127.0.0.1:9999"}
PY
echo "ok: Pi settings update is valid and preserves other keys"

for config in "$ROOT_DIR"/config/*.conf; do
  # shellcheck source=/dev/null
  MODELS_DIR="$ROOT_DIR/models" source "$config"
  for name in MODEL_KEY MODEL_LABEL MODEL_PATH PORT_DEFAULT ALIAS CTX_SIZE SPEC_MODE; do
    [[ -n "${!name:-}" ]] || { echo "FAIL: $config does not define $name" >&2; failures=$((failures + 1)); }
  done
  declare -F pre_launch build_extra_args build_spec_args >/dev/null || {
    echo "FAIL: $config does not implement config function contract" >&2; failures=$((failures + 1));
  }
  unset MODEL_KEY MODEL_LABEL MODEL_PATH PORT_DEFAULT ALIAS CTX_SIZE SPEC_MODE MTP_PATH
done
echo "ok: model configs implement the common contract"

(( failures == 0 )) || exit 1
echo "All tests passed."
