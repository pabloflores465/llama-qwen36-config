#!/usr/bin/env bash
# Shared lifecycle helpers for the single llama-server instance.

state_value() {
  local key="$1" file="$2"
  [[ -f "$file" ]] && sed -n "s/^${key}=//p" "$file" | head -1
}

valid_pid() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] && kill -0 "$1" 2>/dev/null
}

is_llama_server_pid() {
  local pid="${1:-}" command
  valid_pid "$pid" || return 1
  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  [[ "$command" == *llama-server* ]]
}

pid_listens_on_port() {
  local pid="$1" port="$2"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  lsof -nP -a -p "$pid" -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | grep -qx "$pid"
}

server_matches_state() {
  local state_file="$1" pid port url
  [[ -f "$state_file" ]] || return 1
  pid="$(state_value pid "$state_file")"
  port="$(state_value port "$state_file")"
  url="$(state_value url "$state_file")"
  is_llama_server_pid "$pid" || return 1
  pid_listens_on_port "$pid" "$port" || return 1
  curl -fsS --max-time 2 "$url/health" >/dev/null 2>&1
}

default_pi_urls() {
  local config_dir="$1" ports
  # The literal text below matches the shell-default expression in configs.
  # shellcheck disable=SC2016
  ports="$(sed -n 's/^PORT_DEFAULT="${PORT_DEFAULT:-\([0-9][0-9]*\)}"$/\1/p' "$config_dir"/*.conf 2>/dev/null | sort -nu)"
  local out="" port
  while IFS= read -r port; do
    [[ -n "$port" ]] || continue
    out+="${out:+;}http://127.0.0.1:$port"
  done <<<"$ports"
  printf '%s\n' "$out"
}

set_pi_urls() {
  local settings="$1" urls="$2"
  mkdir -p "$(dirname "$settings")"
  [[ -f "$settings" ]] || printf '{}\n' >"$settings"
  python3 - "$settings" "$urls" <<'PY'
import json, os, sys, tempfile
path, urls = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except (OSError, ValueError):
    data = {}
data["llamaServerUrl"] = urls
directory = os.path.dirname(path)
fd, tmp = tempfile.mkstemp(prefix="settings.", suffix=".tmp", dir=directory, text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
except BaseException:
    try: os.unlink(tmp)
    except OSError: pass
    raise
PY
}
