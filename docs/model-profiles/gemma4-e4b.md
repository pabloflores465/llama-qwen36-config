# Gemma 4 E4B QAT

Config: [`config/gemma4-e4b.conf`](../../config/gemma4-e4b.conf)

`gemma4-e4b` is the smaller Gemma option. It follows the same operational model
as the 12B profile: QAT Q4_0 weights, BF16 projector, external Q8 MTP assistant,
long context ceiling, single request slot and Metal-first execution. Choose it
when you prefer Gemma behavior but want a lower-capacity profile than 12B.

## Assets and identity

| Setting | Default | Decision |
|---|---|---|
| `MODEL_PATH` | `gemma-4-E4B-it-QAT-Q4_0.gguf` | QAT Q4_0 fits the quality/memory target of the M5/16 GB baseline. |
| `MMPROJ_PATH` | `mmproj-gemma-4-E4B-it-QAT-BF16.gguf` | Enables image input with a full-precision projector. |
| `MTP_PATH` | `mtp-gemma-4-E4B-it.gguf` | Required for the default external MTP mode. |
| `ALIAS` | `gemma-4-e4b-qat` | Used by API and benchmark verification. |
| `PORT_DEFAULT` | `8081` | Canonical single-server endpoint. |

## Runtime decisions

The profile retains `CTX_SIZE=122880`, `BATCH_SIZE=2048`, `UBATCH_SIZE=512` and
full GPU-layer request (`N_GPU_LAYERS=-1`). It uses four performance cores for
generation and eight batch threads on the target Mac. K/V cache q4_1, Flash
Attention, KV/operation offload and `PARALLEL=1` make long single-session use
the priority.

The hardware target matters more than the model label. A Mac with more unified
memory can raise context or parallelism; a smaller Mac should lower context and
microbatch before touching quantization or offload.

## Checkpoints and cache

Like the 12B profile, E4B uses `CTX_CHECKPOINTS=1`, not the llama.cpp default.
Gemma checkpoint memory can be substantial, and one checkpoint is the safer
starting point on 16 GB. `CACHE_RAM=512`, `CACHE_REUSE=0` and the 16K minimum
checkpoint step avoid uncontrolled cache growth.

No disk slots are configured. The active multimodal projector makes upstream
slot serialization unsupported.

## Speculation

MTP is on by default with one token minimum and maximum. The Q8 assistant is
offloaded to Metal and uses q8_0 draft KV. `SPEC_MODE=none` is the correct
baseline when testing whether the assistant helps a specific prompt. `ngram`
is available for repeated text patterns but does not create a persistent lookup
file for Gemma.

```bash
./server/start.sh gemma4-e4b
SPEC_MODE=none ./server/start.sh gemma4-e4b
CTX_SIZE=65536 CTX_CHECKPOINTS=0 ./server/start.sh gemma4-e4b
```

## Flags inherited through `build_extra_args`

The profile uses Jinja templates, continuous batching, in-memory prompt cache,
metrics and verbosity level 3. `--no-warmup` moves initialization cost to the
first real request; `--fit off` ensures llama.cpp does not alter the explicit
Metal placement plan at runtime.
