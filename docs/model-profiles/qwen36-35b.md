# Qwen 3.6 35B A3B MTP

Config: [`config/qwen36-35b.conf`](../../config/qwen36-35b.conf)

`qwen36-35b` is the largest and most memory-sensitive profile. It runs an IQ2_M Qwen 3.6 35B A3B MoE model with a BF16 projector on a 16 GB unified-memory Mac. It is capability-first, not a low-latency default.

## Assets and identity

| Setting | Default | Why it is selected |
|---|---|---|
| `MODEL_PATH` | `Qwen3.6-35B-A3B-UD-IQ2_M.gguf` | IQ2_M makes this large MoE model plausible on 16 GB. |
| `MMPROJ_PATH` | `mmproj-BF16.gguf` | Keeps image input enabled. |
| `IMAGE_MIN_TOKENS` | `1024` | Avoids overly aggressive visual downsampling. |
| `ALIAS` | `Qwen3.6-35B-A3B-MTP-IQ2_M` | API identity used by state and benchmark validation. |

## Memory-first placement

`--cpu-moe` keeps experts on CPU. `N_GPU_LAYERS=1` is deliberately much lower than the smaller profiles. KV and operation offload remain enabled where they fit, while `--fit on --fit-target 2048` asks llama.cpp to retain headroom.

The profile uses q4_0 KV, Flash Attention, one parallel request, 512 MiB prompt cache and a 122,880-token ceiling. `BATCH_SIZE=2048` preserves prompt throughput, while `UBATCH_SIZE=1024` reduces peak allocation. Decode uses four performance cores; batch work uses eight.

## Guard, checkpoints and MTP

`MEMORY_GUARD=1` reads `memory_pressure` and refuses startup below 20% free memory. It protects the desktop but cannot predict every allocation. If the server dies after load, lower context or microbatch before disabling the guard.

Eight context checkpoints at 16,384-token intervals can help long sessions but cost memory. MTP is disabled by default because draft work may not repay its cost on this CPU-heavy MoE profile.

```bash
CTX_SIZE=65536 ./server/start.sh qwen36-35b
CTX_SIZE=32768 UBATCH_SIZE=512 CTX_CHECKPOINTS=0 ./server/start.sh qwen36-35b
SPEC_MODE=mtp CTX_SIZE=65536 ./server/start.sh qwen36-35b
```

The second command is the stability baseline for diagnosing memory failures. When using MTP, compare it directly with `SPEC_MODE=none` on identical prompts.
