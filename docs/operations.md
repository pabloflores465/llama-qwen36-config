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
looks like `llama-server`, and owns the recorded port. It sends TERM, waits six
seconds, then uses KILL only for that verified process. If metadata is stale it
removes it without killing a process it cannot identify.

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
assume a family; it measures whatever the state records.

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
