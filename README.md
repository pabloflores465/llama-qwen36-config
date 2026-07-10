# Local llama.cpp Qwen3.6 Config

Stable local `llama-server` scripts for running Qwen3.6-35B-A3B-MTP GGUF on Apple Silicon with 16 GB unified memory.

## Scripts

```bash
scripts/start-qwen36-llamacpp.sh
scripts/stop-qwen36-llamacpp.sh
```

## Current default profile

On a 16 GB Mac, `PROFILE=auto` selects `fullctx16`:

```bash
CTX_SIZE=262144
BATCH_SIZE=256
UBATCH_SIZE=128
N_GPU_LAYERS=0
KV_OFFLOAD=0
OP_OFFLOAD=1
FLASH_ATTN=on
CACHE_TYPE_K=q4_0
CACHE_TYPE_V=q4_0
ENABLE_MTP=0
```

## Start

```bash
cd scripts
./start-qwen36-llamacpp.sh
```

Server URL:

```text
http://127.0.0.1:8081
```

## Stop

```bash
cd scripts
./stop-qwen36-llamacpp.sh
```

## Notes

- Model files are intentionally ignored by git.
- Logs and PID files are ignored.
- `q4_0/q4_0` KV cache requires `FLASH_ATTN=on` with this llama.cpp build.
- MTP is disabled by default because it benchmarked slower on this CPU/RAM setup.
