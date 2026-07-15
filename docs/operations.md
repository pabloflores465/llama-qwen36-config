# Operations reference

This page documents every executable maintained by the repository. All commands
expect the repository root as their working directory unless otherwise noted.

## `server/start.sh`

Usage:

```bash
./server/start.sh [model-key] [port]
```

This is the only supported launcher. It sources `config/<model-key>.conf`, builds
one safe Bash argument array and starts `llama-server`. It then waits up to
`HEALTH_TIMEOUT` seconds, default 180, for `/health` before publishing state.

Important environment overrides include `HOST`, `PORT`, `LOG_FILE`, `FOREGROUND`
and every `${NAME:-default}` value in the selected config. `FOREGROUND=1` still
starts a child process, verifies health and writes state; it then waits for the
child and forwards SIGINT/SIGTERM.

The launch log begins with the exact escaped command. Inspect it first after an
asset, memory, Metal or unsupported-flag failure.

## `server/stop.sh`

Usage:

```bash
./server/stop.sh
```

The script reads `models/.run/server.state`, validates that the PID is alive,
looks like `llama-server`, and owns the recorded port. It sends TERM, allowing
six seconds for a single-model server or 30 seconds for a router to stop its
workers, then uses KILL only for that verified process. If metadata is stale it
removes it without killing a process it cannot identify.

## `server/router.sh` and `server/model_swap.sh`

Run `./server/router.sh [port]` once to keep a router listening on the canonical
endpoint. It generates `models/.run/router-models.ini` from the available
`config/*.conf` profiles and limits the router to one loaded model.

```bash
./server/model_swap.sh gemma4-e4b
./server/model_swap.sh qwen35-4b
```

The swap command unloads the current worker, loads the target through the
router API, and updates `server.state`. Editing a profile requires one router
restart to regenerate the preset file.

The router also starts `server/searxng-mcp.mjs` on `127.0.0.1:8765` and applies
`config/webui.json`, exposing the local SearXNG service at `127.0.0.1:8080` as a
`web_search` MCP tool in the built-in Web UI. The bridge listens only on
loopback, allows browser requests from the local Web UI, and is stopped by
`server/stop.sh`. Set `SEARXNG_MCP_ENABLED=0` to launch the router without it;
`SEARXNG_URL`, `SEARXNG_MCP_HOST`, and `SEARXNG_MCP_PORT` override its endpoints.

The router enables llama.cpp's `read_file`, `file_glob_search`, `grep_search`,
`exec_shell_command`, `write_file`, `edit_file`, and `apply_diff` built-in tools
for the Web UI. They run with the router process's user permissions and working
directory, so the router must remain bound to loopback. Set
`WEBUI_BUILTIN_TOOLS=` to disable them or provide a narrower comma-separated
allowlist for one launch. Do not expose this configuration to a network.

## `server/lib.sh`

This is not a user entry point. It provides the shared state parser, PID and
port ownership checks, health check, and atomic Pi settings writer used by
start, stop and benchmark scripts. `server.state` is deliberately plain
`key=value` text so it can be inspected from a shell, but consumers must use
these helpers rather than trust its PID blindly.

## `bench/bench.sh`

Usage:

```bash
./bench/bench.sh
MATRIX='2048:128 16384:64' OUT=logs/run.jsonl ./bench/bench.sh
```

It verifies a healthy state and alias, calibrates text to the selected model's
tokenizer through `/tokenize`, sends `/completion`, and appends JSONL records.
The default matrix is `2048:128 16384:64 65536:32`. The generic runner does not
assume a family; it measures whatever the state records. On macOS it also emits
`memory_pressure` rows before and after every request. These include the free
percentage, page size, wired/compressor pages, pageins/pageouts and swap
counters, so pressure deltas can be compared without conflating them with RSS.

`bench/qwen35-bench.sh`, `bench/gemma4-bench.sh`, and
`bench/bench-gemma4-12b.sh` are deliberately small wrappers. They set an
expected family so a Qwen benchmark cannot silently measure Gemma, or vice
versa.

## Tests and CI

`tests/lint.sh` runs Bash syntax checks and ShellCheck with sourced-file support.
`tests/test.sh` validates the config interface, Pi settings update and canonical
port behavior without launching a model. `tests/integration.sh` copies the
launcher/config into a temporary directory and uses `fake-llama-server.py` to
test launch and stop behavior over a real loopback HTTP port.

`.github/workflows/ci.yml` installs ShellCheck and runs all three checks on
Ubuntu. The integration test is intentionally model-free, so CI does not need
to download several GB of weights.

## Compatibility wrappers

`scripts/start-qwen36-llamacpp.sh` and `scripts/stop-qwen36-llamacpp.sh` exist
only for old automation. The start wrapper calls the new launcher with
`qwen36-35b`; the stop wrapper delegates to the verified stop script. New code
should not add more wrappers.

## Pi settings

`.pi/settings.example.json` is the portable template. The actual
`.pi/settings.json` is ignored because it is local runtime configuration. Start
sets its `llamaServerUrl` to the live endpoint; stop returns it to canonical
`http://127.0.0.1:8081`. Global Pi settings may exist separately under
`~/.pi/agent/settings.json`, but project settings take precedence.
