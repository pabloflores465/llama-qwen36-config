# Gemma 4 12B Q4_K_M

Config: [`config/gemma4-12b.conf`](../../config/gemma4-12b.conf)

`gemma4-12b` is the repository default. It pairs Unsloth's non-QAT Q4_K_M main
weights with the repository's BF16 multimodal projector and root-level Q8_0 MTP
assistant. It is the balanced Gemma profile when you want vision, a long
context ceiling and external speculative decoding without moving to the much
larger Qwen 3.6 MoE profile.

## Assets and identity

| Setting | Default | Decision |
|---|---|---|
| `MODEL_PATH` | `gemma-4-12b-it-Q4_K_M.gguf` | Standard Q4_K_M is the requested non-QAT 4-bit test variant. |
| `MMPROJ_PATH` | `mmproj-BF16.gguf` | Matching BF16 projector from the same Unsloth repository preserves the vision encoder representation. |
| `MTP_PATH` | `mtp-gemma-4-12b-it.gguf` | Gemma uses a separate assistant file for MTP; startup fails if MTP is requested and it is absent. |
| `ENABLE_MMPROJ` | `1` | Vision is the intended mode. Disabling it is diagnostic only, not the documented workflow. |
| `ALIAS` | `gemma-4-12b` | This exact ID must appear in `/v1/models`; benchmarks use it to prevent measuring the wrong server. |
| `PORT_DEFAULT` | `8081` | One server runs at a time, so all profiles share Pi's canonical endpoint. |

## Context, CPU and memory profile

`CTX_SIZE=122880` leaves room for long coding or document sessions. It is a
ceiling, not a claim that every workload will fit comfortably alongside other
macOS applications. Reduce it first when swap, UI stutter or startup failure
appears.

Generation uses the detected performance-core count, four on the target M5.
Prompt ingestion uses twice that number, eight, because prefill parallelizes
better than token-by-token decode. `BATCH_SIZE=2048` favors prompt throughput;
`UBATCH_SIZE=512` limits the peak compute allocation.

`N_GPU_LAYERS=-1`, KV offload, operation offload and Flash Attention prioritize
Metal/unified-memory throughput. KV K/V are q4_1 rather than fp16, reducing the
long-context memory footprint. `PARALLEL=1` reserves the whole context for one
agent session instead of splitting memory across simultaneous requests.

## Cache and checkpoint decisions

`CACHE_RAM=512` bounds the reusable prompt-cache RAM budget. `CACHE_REUSE=0`
avoids aggressive reuse heuristics. The profile uses exactly one context
checkpoint and a minimum 16,384-token step. Gemma checkpoints can be large on a
16 GB machine; one checkpoint gives a recovery point without allowing a queue of
snapshots to consume several GB. Raise it only after observing RSS and swap.

Disk slot save/restore is intentionally absent. With `--mmproj`, current
llama.cpp rejects that API; a `.bin` snapshot is not a supported persistence
mechanism for this profile.

## Speculative decoding

`SPEC_MODE=mtp` is the default. The main model verifies proposals from the Q8
assistant. `DRAFT_N_MIN=1` and `DRAFT_N_MAX=3` balance proposal acceptance and
verification work on the target M5: the measured 2,048-prompt/128-generation
benchmark improved decode throughput by about 24% over a maximum draft length
of one. The draft is fully offloaded with `--spec-draft-ngl -1`; its draft KV
remains q8_0.

Available modes:

```bash
SPEC_MODE=none ./server/start.sh gemma4-12b
SPEC_MODE=mtp ./server/start.sh gemma4-12b
SPEC_MODE=ngram ./server/start.sh gemma4-12b
```

`ngram` uses llama.cpp's n-gram modifier, not the Qwen persistent lookup-cache
mode. Benchmark it rather than assuming it is faster for natural language.

## Model-specific server flags

- `--jinja` uses the chat template embedded in the model; there is no external
  tool-calling template override.
- `--cont-batching` lets the server schedule prompts efficiently.
- `--cache-prompt` and `--cache-idle-slots` preserve in-memory request cache
  behavior; they are not disk persistence.
- `--metrics` exposes server metrics.
- `--no-warmup` avoids a synthetic allocation at startup, so first-request cost
  may be higher.
- `--fit off` preserves the explicitly selected offload plan.
- `--verbosity 3` records operational diagnostics in the model log.

## Practical starting commands

```bash
./server/start.sh gemma4-12b
CTX_SIZE=65536 ./server/start.sh gemma4-12b
SPEC_MODE=none CTX_CHECKPOINTS=0 ./server/start.sh gemma4-12b
```

The second command is the first response to memory pressure. The third is a
useful control run when comparing MTP and checkpoint overhead.
