# Qwen 3.5 4B MTP

Config: [`config/qwen35-4b.conf`](../../config/qwen35-4b.conf)

`qwen35-4b` is the fast-iteration Qwen profile. Use it first to validate an agent workflow, tool format, long-prompt shape or image request before spending more time and unified memory on a larger model.

## Assets and identity

| Setting | Default | Why it is selected |
|---|---|---|
| `MODEL_PATH` | `Qwen3.5-4B-UD-Q4_K_XL.gguf` | Q4_K_XL is the chosen local quality/size balance. |
| `MMPROJ_PATH` | `mmproj-BF16.gguf` | Enables vision while retaining projector fidelity. |
| `IMAGE_MIN_TOKENS` | `1024` | Keeps a minimum visual-token budget for dynamic resolution. |
| `ALIAS` | `Qwen3.5-4B-MTP-Q4_K_XL` | API identity checked by the benchmark. |
| `LOOKUP_CACHE` | user cache path | Used only by n-gram speculative modes. |

## Runtime profile

The 122,880-token context is paired with q4_0 KV cache and Flash Attention. On the M5 baseline, decode uses four performance cores and prefill uses eight threads. `BATCH_SIZE=2048` favors prompt throughput; `UBATCH_SIZE=512` bounds peak compute allocation. All layers request Metal offload, and KV plus operation offload remain enabled.

`PARALLEL=1` reserves the full context for one coding or agent request. The 512 MiB prompt-cache budget and `CACHE_REUSE=0` avoid uncontrolled cache growth. Eight context checkpoints at a 16,384-token minimum support long sessions; lower `CTX_CHECKPOINTS` before lowering model quality if memory use is too high.

## Reasoning and speculation

Jinja, continuous batching and automatic DeepSeek-format reasoning are enabled for client compatibility. The built-in MTP head proposes one to three tokens; it needs no assistant GGUF. N-gram modes initialize a lookup cache with `llama-lookup-create`. That file is reusable pattern data, not a saved chat.

```bash
SPEC_MODE=mtp ./server/start.sh qwen35-4b
SPEC_MODE=none ./server/start.sh qwen35-4b
SPEC_MODE=ngram ./server/start.sh qwen35-4b
SPEC_MODE=mtp-ngram ./server/start.sh qwen35-4b
```

Use `none` as the benchmark control. N-gram is most likely to help repetitive source patterns and should not be assumed to help novel prose or images.

## Useful experiments

```bash
CTX_SIZE=65536 CTX_CHECKPOINTS=4 ./server/start.sh qwen35-4b
IMAGE_MIN_TOKENS=1536 ./server/start.sh qwen35-4b
THREADS=4 THREADS_BATCH=8 ./server/start.sh qwen35-4b
```

Benchmark a single changed setting at a time and compare output quality as well as prompt rate, generation rate and RSS.
