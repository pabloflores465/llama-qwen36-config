# Model and server parameters

The defaults are conservative operating choices, not universal optima. Override
any default for one launch, for example:

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

## Context and concurrency

- `CTX_SIZE`: maximum context tokens allocated by the server. Larger values
  preserve longer sessions but increase KV-cache memory and startup pressure.
- `PARALLEL`: number of concurrent slots. `1` dedicates the full context and
  memory budget to one agent session.
- `CTX_CHECKPOINTS`: number of reusable context checkpoints retained by Qwen.
  More checkpoints can accelerate branching/repeated prompts at a RAM cost.
- `CHECKPOINT_MIN_STEP`: minimum token distance between checkpoints; a large
  value limits checkpoint overhead on long contexts.
- `CACHE_REUSE`: token-distance threshold for prompt cache reuse. Zero leaves
  reuse decisions to exact cached prefixes and avoids aggressive reuse.
- `CACHE_RAM`: MiB budget for the server's reusable prompt cache.

## CPU, GPU and batching

- `THREADS`: CPU threads during token generation. Generation is latency-sensitive;
  too many threads can contend with macOS and reduce throughput.
- `THREADS_BATCH`: CPU threads during prompt ingestion, which parallelizes better
  than generation. Qwen 3.5 uses more batch threads for faster prompt processing.
- `BATCH_SIZE`: logical maximum tokens processed in one prompt batch. Larger
  batches improve throughput until memory bandwidth or allocation pressure wins.
- `UBATCH_SIZE`: physical compute microbatch. Lower it to reduce peak memory;
  Qwen 3.6 uses 2048 because its CPU-MoE/offload profile was tuned for it.
- `N_GPU_LAYERS`: layers placed on Metal. `-1` requests maximum offload; Qwen 3.6
  uses `1` because its 35B MoE weights must fit alongside macOS in 16 GB.
- `KV_OFFLOAD`: stores/operates the KV cache on GPU when enabled. This is faster
  when memory permits, but large contexts consume substantial unified memory.
- `OP_OFFLOAD`: allows graph operations on GPU. It usually improves throughput
  on Apple Silicon at the cost of additional Metal allocations.
- `--cpu-moe`: Qwen 3.6 keeps MoE experts on CPU to avoid exhausting Metal memory.
- `--fit` and `FIT_TARGET`: Qwen 3.6 lets llama.cpp adjust placement toward a
  target free-memory margin; Gemma/Qwen 3.5 use fixed `--fit off` behavior.

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

## Vision, reliability and observability

- `IMAGE_MIN_TOKENS`: minimum image-token budget for Qwen projectors; prevents
  overly aggressive downscaling of visual inputs.
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
