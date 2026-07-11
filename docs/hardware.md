# Hardware baseline

The checked-in defaults are tuned for this machine, not for every Apple
Silicon Mac:

```text
Model:       MacBook Pro Mac17,2
SoC:         Apple M5
CPU:         4 performance cores + 6 efficiency cores (10 total)
GPU:         10-core Apple M5 GPU, Metal supported
Memory:      16 GB unified memory
```

## Why these defaults

- Generation defaults to the 4 performance cores. Using all 10 cores for every
  decode step competes with macOS and can increase latency or memory pressure.
- Prompt ingestion gets `2 * performance_cores` threads by default. It is more
  parallel than decode while leaving efficiency cores available to the system.
- Metal remains the primary execution path: `N_GPU_LAYERS=-1` for the smaller
  models and a conservative `1` plus `--cpu-moe` for Qwen 3.6 35B A3B.
- Flash attention and quantized KV caches are enabled to make long contexts fit
  within unified memory.
- Gemma defaults to one context checkpoint. Gemma checkpoints are unusually
  large and can exhaust RAM on 16 GB systems; increase it only after measuring.
- Qwen 3.6 uses a 1024 microbatch rather than 2048 to reduce peak allocation
  while retaining a 2048 logical prompt batch.
- All models retain multimodal projectors by default, because vision is part of
  the intended workload. Disk slot persistence is not enabled upstream for
  multimodal contexts.

## Overrides for experiments

The defaults are a safe starting point, not a benchmark conclusion. Override
one launch without editing files:

```bash
THREADS=6 THREADS_BATCH=10 ./server/start.sh qwen35-9b
CTX_SIZE=65536 CTX_CHECKPOINTS=0 ./server/start.sh gemma4-12b
UBATCH_SIZE=512 ./server/start.sh qwen36-35b
```

Use `memory_pressure` before and after long runs. If swap activity rises or the
desktop becomes sluggish, reduce `CTX_SIZE`, `BATCH_SIZE`, `UBATCH_SIZE`, or
`CTX_CHECKPOINTS` before increasing offload.

## Portability

On a Mac with a different core split or memory size, override `PERF_CORES`,
`THREADS`, `THREADS_BATCH`, context and batch sizes. The configs detect
`hw.perflevel0.physicalcpu` when available and fall back to 4 performance cores.
