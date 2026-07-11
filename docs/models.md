# Supported models

All defaults target Apple Silicon with 16 GB unified memory and a single request
slot. Paths are relative to the ignored `models/` directory.

| Key | Default port | Quantization | Vision | Speculation | Notes |
|---|---:|---|---|---|---|
| `gemma4-12b` | 8082 | QAT Q4_0 | BF16 mmproj | external Q8 MTP | Dense 12B; MTP default |
| `gemma4-e4b` | 8083 | QAT Q4_0 | BF16 mmproj | external Q8 MTP | Smaller Gemma variant |
| `qwen35-4b` | 8084 | UD Q4_K_XL | BF16 mmproj | built-in MTP/ngram | Fastest Qwen profile |
| `qwen35-9b` | 8089 | UD Q4_K_XL | BF16 mmproj | built-in MTP/ngram | Higher quality, more memory |
| `qwen36-35b` | 8081 | UD IQ2_M | BF16 mmproj | built-in MTP | MoE; CPU experts; MTP off by default |

## Choosing a model

- Use Qwen 3.5 4B for latency and routine tool work.
- Use Qwen 3.5 9B when quality is more important than latency.
- Use Gemma 4 when its instruction style or multimodal behavior fits the task.
- Use Qwen 3.6 35B A3B for the strongest local reasoning profile, accepting
  slower CPU-MoE execution and tighter memory margins.

Disable vision with `ENABLE_MMPROJ=0` when images are unnecessary or disk slot
persistence is required. The slot save/restore API may return HTTP 501 while a
multimodal projector is loaded.

## Adding a model

Copy the closest config, choose a unique key and default port, implement the
three config functions, then run `./tests/test.sh`. `server/stop.sh` derives the
Pi discovery URL list from all `PORT_DEFAULT` values automatically.
