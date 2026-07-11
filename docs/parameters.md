# Configuration parameters and decisions

The config files are shell-sourced by `server/start.sh`. A value written as
`${NAME:-default}` can be supplied as an environment variable for one launch;
the profile then emits the corresponding llama.cpp argument. The defaults are
conservative choices for the documented M5/16 GB machine, not universal optima.

```bash
CTX_SIZE=32768 SPEC_MODE=none ./server/start.sh qwen35-9b
```

## Identity and files

- `MODEL_PATH`: main GGUF weights loaded by `llama-server`.
- `MMPROJ_PATH`: vision projector translating image embeddings for the model.
- `MTP_PATH`: separate draft/MTP model used by Gemma speculative decoding.
- `ENABLE_MMPROJ`: loads vision support when `1`, which is the default for every
  supported model. Disabling it is only a diagnostic escape hatch.
- `ALIAS`: model identifier exposed through `/v1/models`; clients and benchmarks
  use it to verify that they reached the intended server.
- `PORT_DEFAULT`: canonical listening port, `8081` for every model because this
  repository runs only one server. Override it with the second argument or `PORT`.

`MODEL_KEY` identifies the config file and becomes the `model` field in runtime
state. `MODEL_LABEL` is operator-facing text. Neither is sent to llama.cpp;
`ALIAS` is the server-visible identity. Keep aliases stable because benchmarks
validate them through `/v1/models`.

## Context and concurrency

- `CTX_SIZE`: maximum context tokens allocated by the server. Larger values
  preserve longer sessions but increase KV-cache memory, graph allocation and
  startup pressure. On this 16 GB machine, lower it before reducing model
  quality when memory is tight.
- `PARALLEL`: number of concurrent slots. `1` dedicates the full context and
  memory budget to one agent session.
- `CTX_CHECKPOINTS`: number of reusable context checkpoints retained by the
  server. More can accelerate branching/repeated prompts at a RAM cost. Gemma
  uses `1` because its snapshots can be exceptionally large; Qwen uses `8` for
  long agent sessions.
- `CHECKPOINT_MIN_STEP`: minimum token distance between checkpoints; a large
  value limits checkpoint overhead on long contexts.
- `CACHE_REUSE`: token-distance threshold for prompt cache reuse. Zero leaves
  reuse decisions to exact cached prefixes and avoids aggressive reuse.
- `CACHE_RAM`: MiB budget for the server's reusable prompt cache.

Context checkpoints, prompt cache and the removed disk slot API are different.
The first two are in-memory server optimizations. They do not create a portable,
resumable conversation file, and they should not be confused with application
chat history.

## CPU, GPU and batching

- `THREADS`: CPU threads during token generation. Generation is latency-sensitive;
  too many threads can contend with macOS and reduce throughput. `PERF_CORES`
  detects `hw.perflevel0.physicalcpu` and defaults to four on the target M5.
- `THREADS_BATCH`: CPU threads during prompt ingestion, which parallelizes better
  than generation. Qwen 3.5 uses more batch threads for faster prompt processing.
- `BATCH_SIZE`: logical maximum tokens processed in one prompt batch. Larger
  batches improve throughput until memory bandwidth or allocation pressure wins.
- `UBATCH_SIZE`: physical compute microbatch. Lower it to reduce peak memory;
  Qwen 3.6 uses `1024` because its CPU-MoE/offload profile has the tightest peak
  allocation on 16 GB.
- `N_GPU_LAYERS`: layers placed on Metal. `-1` requests maximum offload; Qwen 3.6
  uses `1` because its 35B MoE weights must fit alongside macOS in 16 GB.
- `KV_OFFLOAD`: stores/operates the KV cache on GPU when enabled. This is faster
  when memory permits, but large contexts consume substantial unified memory.
- `OP_OFFLOAD`: allows graph operations on GPU. It usually improves throughput
  on Apple Silicon at the cost of additional Metal allocations.
- `--cpu-moe`: Qwen 3.6 keeps MoE experts on CPU to avoid exhausting Metal memory.
- `--fit` and `FIT_TARGET`: Qwen 3.6 lets llama.cpp adjust placement toward a
  target free-memory margin; Gemma/Qwen 3.5 use fixed `--fit off` behavior.

The common launcher always adds `--split-mode layer`, `--kv-unified`, host,
port, model path, alias and the common cache/offload arguments. Config builders
add the remaining model-specific flags. `N_GPU_LAYERS=-1` asks llama.cpp to
offload as much as feasible; it does not guarantee the same placement across
llama.cpp builds or available unified memory.

## KV cache and attention

- `CACHE_TYPE_K` / `CACHE_TYPE_V`: quantization of key/value cache tensors.
  `q4_0` and `q4_1` greatly reduce long-context memory versus FP16, trading a
  small amount of quality. Gemma uses q4_1; Qwen uses q4_0.
- `FLASH_ATTN`: fused attention implementation. `on` reduces memory traffic and
  is required by some quantized KV-cache combinations in llama.cpp.
- `--kv-unified`: shares a unified KV allocation across slots, reducing redundant
  allocation and matching this repository's single-slot architecture.

## Speculative decoding

- `SPEC_MODE=none`: normal autoregressive generation; lowest extra memory.
- `SPEC_MODE=mtp`: predicts multiple future tokens with an MTP head/model and
  verifies them with the main model. It helps only when acceptance offsets draft
  overhead; therefore Qwen 3.6 disables it by default on this CPU-heavy profile.
- `SPEC_MODE=ngram`: drafts repeated sequences from a persistent lookup cache.
  It is cheap and useful for repetitive code/text, but offers little on novel text.
- `SPEC_MODE=mtp-ngram`: combines both Qwen 3.5 draft sources.
- `DRAFT_N_MIN` / `DRAFT_N_MAX`: minimum/maximum draft length. Larger drafts can
  accelerate predictable output but waste work when acceptance is low.
- `DRAFT_CACHE_TYPE_K/V`: KV quantization for the draft path.
- `NGRAM_N_MIN`, `NGRAM_N_MAX`, `NGRAM_N_MATCH`: n-gram candidate lengths and
  required match depth; higher match depth favors precision over opportunities.
- `LOOKUP_CACHE`: persistent n-gram database, initialized on first use.

Gemma MTP uses a separate `MTP_PATH` assistant GGUF and conservative one-token
drafts. Qwen 3.5 uses its built-in MTP head and permits up to three drafts. Qwen
3.6 also has an MTP head but defaults to `none` because its CPU-MoE path often
does not benefit from draft overhead on this hardware.

## Vision, reliability and observability

- `IMAGE_MIN_TOKENS`: minimum image-token budget for Qwen projectors; prevents
  overly aggressive downscaling of visual inputs.
- `--jinja`: enables the model chat template. It prevents clients from needing
  to construct model-special token syntax themselves.
- `--cont-batching`: allows the server scheduler to process compatible work more
  efficiently. It does not change the deliberate `PARALLEL=1` memory policy.
- `--cache-prompt` / `--cache-idle-slots`: retain in-memory prompt cache behavior
  for an idle request slot. They are not disk slot persistence.
- `--reasoning auto --reasoning-format deepseek`: Qwen profiles let llama.cpp
  detect reasoning behavior and expose compatible reasoning content.
- `MEMORY_GUARD` / `MIN_FREE_PCT`: Qwen 3.6 refuses startup under memory pressure
  to protect WindowServer and avoid swap/display instability.
- `HEALTH_TIMEOUT`: seconds startup waits for `/health` before rolling back.
- `FOREGROUND`: when `1`, keeps the launcher attached while retaining the same
  health checks and state semantics as background mode.
- `--metrics`: exposes Prometheus metrics for diagnostics.
- `--no-warmup`: avoids a synthetic warmup allocation; actual first request may
  consequently include one-time initialization cost.
- `--verbosity`: llama.cpp log detail. Level 3 provides useful operational data
  without maximum trace volume.

## Profile default matrix

| Parameter | Gemma 12B | Gemma E4B | Qwen 3.5 4B | Qwen 3.5 9B | Qwen 3.6 35B |
|---|---:|---:|---:|---:|---:|
| Context | 122880 | 122880 | 122880 | 122880 | 122880 |
| Decode / batch threads | 4 / 8 | 4 / 8 | 4 / 8 | 4 / 8 | 4 / 8 |
| Batch / microbatch | 2048 / 512 | 2048 / 512 | 2048 / 512 | 2048 / 512 | 2048 / 1024 |
| KV cache | q4_1 / q4_1 | q4_1 / q4_1 | q4_0 / q4_0 | q4_0 / q4_0 | q4_0 / q4_0 |
| GPU layers | -1 | -1 | -1 | -1 | 1 |
| Context checkpoints | 1 | 1 | 8 | 8 | 8 |
| Speculation | MTP | MTP | MTP | MTP | none |

Every profile defaults to `ENABLE_MMPROJ=1`, `PARALLEL=1`, `CACHE_RAM=512`,
Flash Attention, KV offload and operation offload. Use the individual profile
documents to understand exceptions and safe experiment orders.
