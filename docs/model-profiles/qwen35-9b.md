# Qwen 3.5 9B MTP

Config: [`config/qwen35-9b.conf`](../../config/qwen35-9b.conf)

`qwen35-9b` is the higher-capacity Qwen option. It retains the same client and server behavior as 4B while trading more unified memory and slower generation for a larger model. Use it after 4B has proven the workflow and the task needs more capability.

## Assets and identity

| Setting | Default | Why it is selected |
|---|---|---|
| `MODEL_PATH` | `Qwen3.5-9B-UD-Q4_K_XL.gguf` | Larger Qwen 3.5 model in the selected local quantization. |
| `MMPROJ_PATH` | `mmproj-BF16.gguf` | Keeps image input enabled. |
| `IMAGE_MIN_TOKENS` | `1024` | Minimum visual representation budget. |
| `ALIAS` | `Qwen3.5-9B-MTP-Q4_K_XL` | Verified by state and benchmark checks. |
| `LOOKUP_CACHE` | user cache path | Used only by n-gram modes. |

## Runtime profile

The 9B profile uses the same M5-oriented CPU policy as 4B: four performance cores for decode and eight batch threads. It requests 122,880 context tokens, 2048 logical batch, 512 microbatch, full Metal layer offload, q4_0 KV cache and Flash Attention.

The larger weights make that context less forgiving when other macOS applications use unified memory. Use `CTX_SIZE=65536` first for stability, then `UBATCH_SIZE=256` or fewer checkpoints. Do not increase parallelism on this 16 GB baseline without measuring peak RSS.

## Cache, reasoning and speculation

`CACHE_RAM=512`, `CACHE_REUSE=0`, eight context checkpoints and a 16,384-token minimum follow the 4B profile. They are memory-managed server state, not durable conversation persistence. Jinja, continuous batching and DeepSeek-format reasoning keep client behavior comparable across Qwen sizes.

The built-in MTP head proposes one to three tokens. `none` is the benchmark control. `ngram` builds a persistent lookup cache on first use, while `mtp-ngram` combines both proposal sources.

```bash
./server/start.sh qwen35-9b
SPEC_MODE=none ./server/start.sh qwen35-9b
SPEC_MODE=ngram ./server/start.sh qwen35-9b
CTX_SIZE=65536 UBATCH_SIZE=256 ./server/start.sh qwen35-9b
```

Use the same prompt and image mix for every mode. MTP acceptance does not by itself establish that the complete request is faster or better.
