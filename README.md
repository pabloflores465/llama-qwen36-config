# Local llama.cpp server

Config-driven local inference for Apple Silicon with 16 GB unified memory. The
repository runs one `llama-server` at a time and integrates it with
`pi-llama-cpp`, multimodal inference and reproducible benchmarks.

## Supported models

| Key | Model | Port | Default speculation |
|---|---|---:|---|
| `qwen36-35b` | Qwen 3.6 35B A3B IQ2_M (MoE) | 8081 | none |
| `gemma4-12b` | Gemma 4 12B QAT Q4_0 | 8081 | MTP |
| `gemma4-e4b` | Gemma 4 E4B QAT Q4_0 | 8081 | MTP |
| `qwen35-4b` | Qwen 3.5 4B Q4_K_XL | 8081 | MTP |
| `qwen35-9b` | Qwen 3.5 9B Q4_K_XL | 8081 | MTP |

All five profiles support vision through a BF16 multimodal projector. See
[model guidance](docs/models.md) and the [parameter reference](docs/parameters.md).

## Quick start

```bash
./server/start.sh                       # defaults to Gemma 4 12B on port 8081
./server/start.sh qwen35-4b             # http://127.0.0.1:8081
./server/start.sh gemma4-12b 9000       # explicit port
SPEC_MODE=none ./server/start.sh qwen35-9b
./server/stop.sh
```

Startup waits until `/health` succeeds. Failed starts roll back PID/state files
and restore Pi's server discovery list. Only one healthy recorded server may run.

## Benchmarks

```bash
./bench/bench.sh
MATRIX='2048:128 16384:64' ./bench/bench.sh
OUT=logs/experiment.jsonl ./bench/qwen35-bench.sh
```

The family wrappers reject the wrong loaded model. JSONL results include the
context, batch, cache, offload and speculation settings from `server.state`.

## Validation

```bash
brew install shellcheck
./tests/lint.sh
./tests/test.sh
```

GitHub Actions runs both checks. Model files, logs, runtime state and personal
`.pi/settings.json` data are not committed; use `.pi/settings.example.json` as
the portable template.

## Documentation

- [Architecture and lifecycle](docs/architecture.md)
- [Supported models and selection](docs/models.md)
- [Why each runtime parameter exists](docs/parameters.md)
- [Legacy `scripts/` compatibility and `process.cwd` recovery](scripts/README.md)

Every setting that uses `${NAME:-default}` can be overridden for one command,
for example `CTX_SIZE=32768 ./server/start.sh qwen36-35b`.
