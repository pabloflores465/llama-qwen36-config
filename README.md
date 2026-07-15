# Local llama.cpp server

This repository is an operational baseline for running one multimodal
`llama-server` at a time on a local Apple Silicon Mac. It centralizes model
profiles, process lifecycle, Pi integration, reproducible benchmarks and safety
checks so changing models does not require a separate launcher for every GGUF.

For hot swaps on one stable endpoint, start `./server/router.sh` once and use
`./server/model_swap.sh <model-key>`. The router remains alive while its model
worker is unloaded and replaced.

The checked-in defaults were tuned for the MacBook Pro M5 with 16 GB unified
memory used to build this repository. They are a conservative starting point,
not universal performance claims. Read [hardware tuning](docs/hardware.md)
before copying values to a different machine.

## What this repository does

- Starts one selected GGUF model through `llama-server` and waits for `/health`
  before declaring success.
- Records the verified process in `models/.run/server.state` so stop and
  benchmark commands operate on the same server.
- Updates the project Pi configuration to the live server URL; Pi uses the
  canonical local endpoint `http://127.0.0.1:8081`.
- Exposes five multimodal profiles, all with their BF16 projector enabled by
  default.
- Writes launch logs and benchmark JSONL without committing models, logs, state
  or personal Pi settings.
- Refuses unsafe conditions such as missing model assets, an occupied port,
  stale metadata or low free memory for the largest profile.

It deliberately does **not** expose llama.cpp disk slot save/restore. Upstream
llama.cpp rejects slot persistence when an `mmproj` is loaded, and all profiles
in this repository are intended for multimodal use.

## Requirements

- macOS on Apple Silicon.
- A current `llama-server`; Qwen n-gram modes also require
  `llama-lookup-create` on `PATH`. The profiles were last checked with llama.cpp
  build 9910.
- Matching GGUF, BF16 projector and, for Gemma MTP, assistant GGUF files under
  the ignored `models/` directory.
- `curl`, `python3`, `lsof` and standard macOS utilities.
- Optional: [Pi Coding Agent](https://pi.dev/) with `pi-llama-cpp` installed.

Run `./tests/lint.sh` to verify local scripting prerequisites. It requires
ShellCheck, available through `brew install shellcheck`.

## Supported profiles

| Key | Weights | Default role | Speculation | Detail |
|---|---|---|---|---|
| `gemma4-12b` | Gemma 4 12B Q4_K_M | Default balanced Gemma | External Q8 MTP | [profile](docs/model-profiles/gemma4-12b.md) |
| `gemma4-e4b` | Gemma 4 E4B QAT Q4_0 | Lighter Gemma option | External Q8 MTP | [profile](docs/model-profiles/gemma4-e4b.md) |
| `qwen35-4b` | Qwen 3.5 4B UD Q4_K_XL | Lowest-latency Qwen | MTP; n-gram optional | [profile](docs/model-profiles/qwen35-4b.md) |
| `qwen35-9b` | Qwen 3.5 9B UD Q4_K_XL | Higher-quality Qwen | MTP; n-gram optional | [profile](docs/model-profiles/qwen35-9b.md) |
| `qwen36-35b` | Qwen 3.6 35B A3B UD IQ2_M | Largest local MoE | Off by default | [profile](docs/model-profiles/qwen36-35b.md) |
| `qwen36-35b-gpu-full` | Qwen 3.6 35B A3B UD IQ2_M | Experimental full Metal, CPU KV | Disabled | [profile](docs/model-profiles/qwen36-35b-gpu-full.md) |

Each profile uses port `8081` by default because this is a single-server
workflow. Pass a second argument to use another port for an experiment.

## Start a model

Run from the repository root:

```bash
./server/start.sh
./server/start.sh qwen35-4b
./server/start.sh gemma4-12b 9000
SPEC_MODE=none ./server/start.sh qwen35-9b
```

With no arguments, the launcher shows a model menu and defaults to
`gemma4-12b`. In a non-interactive shell it uses that default directly.

The launcher loads the profile before resolving its port, clears only stale
metadata, validates the weights and projector, runs model preflight, starts the
process, polls `/health`, writes state atomically, then focuses Pi on the live
URL. It accepts connections only on `127.0.0.1` unless `HOST` is overridden.

## Stop a model

```bash
./server/stop.sh
```

The stop script verifies that the recorded PID is a `llama-server` and owns the
recorded port before signalling it. It cleans stale state but never kills an
unrelated process merely because it uses the same port.

## Runtime files and logs

After a successful launch, inspect:

```bash
cat models/.run/server.state
tail -100 logs/gemma4-12b.log
```

The state records the model, alias, PID, URL, context, batching, cache types,
offload and speculation mode. The benchmark includes those fields in each JSONL
row so results can be compared meaningfully.

`FOREGROUND=1` keeps the launcher attached while preserving the same health and
state semantics:

```bash
FOREGROUND=1 ./server/start.sh qwen35-4b
```

## Pi integration

`pi-llama-cpp` resolves URLs from project settings, environment, global settings
and finally its own default. This repository writes the project setting after a
successful launch, so running `pi` here targets the active local server.

If Pi reports an unreachable server after a crash, run `./server/stop.sh` to
clean metadata and start the intended model again. Do not list inactive ports in
`llamaServerUrl`; Pi will warn about each inactive server.

## Override a parameter for one run

Every profile uses `${NAME:-default}`. Override values without editing tracked
configuration:

```bash
CTX_SIZE=65536 ./server/start.sh gemma4-12b
THREADS=6 THREADS_BATCH=10 ./server/start.sh qwen35-9b
SPEC_MODE=ngram ./server/start.sh qwen35-4b
UBATCH_SIZE=512 MEMORY_GUARD=1 ./server/start.sh qwen36-35b
```

Change one dimension at a time and record the result. Context size, KV cache
types, offload and microbatch size all materially affect unified-memory use.
See [configuration parameters](docs/parameters.md) for tradeoffs.

## Benchmark a running model

```bash
./bench/bench.sh
MATRIX='2048:128 16384:64' ./bench/bench.sh
OUT=logs/qwen35-9b-experiment.jsonl ./bench/qwen35-bench.sh
./bench/gemma4-bench.sh
```

The generic runner validates state, `/health` and the model alias from
`/v1/models`. Family wrappers also reject the wrong model family. Each matrix
item is `prompt_tokens:generation_tokens`; output is JSONL plus a process-memory
row after each request. On macOS, system `memory_pressure` snapshots bracket
each request and record wired/compressed pages, page I/O and swap counters.

The runner sends `cache_prompt=false`, so prompt throughput does not accidentally
measure a warm cache. It compares cold prefill configurations, not cached-chat
latency.

## Validate changes

```bash
brew install shellcheck
./tests/lint.sh
./tests/test.sh
./tests/integration.sh
```

The integration test uses a tiny fake HTTP server, not model weights. It checks
port selection, health-gated startup, state creation and safe shutdown. GitHub
Actions runs lint, unit and integration checks on every push and pull request.

## Documentation

- [Architecture and lifecycle](docs/architecture.md)
- [Operations reference](docs/operations.md)
- [Model selection](docs/models.md)
- [Hardware baseline](docs/hardware.md)
- [Configuration parameters and decisions](docs/parameters.md)
- [Detailed model profiles](docs/model-profiles/README.md)

The original Qwen 3.6 entry points remain as compatibility wrappers in
`scripts/`; new automation should call `server/start.sh` and `server/stop.sh`.
