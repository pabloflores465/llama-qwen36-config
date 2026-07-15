# Qwen 3.6 Metal attention / CPU-MoE experiment

Tested on an Apple M5 MacBook Pro with 16 GiB unified memory using llama.cpp
b9910 and `Qwen3.6-35B-A3B-UD-IQ2_M.gguf`. The controlled server used a 32,768
token context, q4_0 KV, batch 2048, microbatch 512, four decode threads, eight
batch threads, no projector, no prompt RAM cache, no checkpoints and no MTP.
Every variant retained `--cpu-moe`.

## Result

The current `N_GPU_LAYERS=1` placement remains the best usable configuration.
Moving transformer/attention work to Metal did not improve throughput on this
16 GiB unified-memory system. It pinned enough memory to cause compression,
swap or Metal out-of-memory errors, and the smallest meaningful split was much
slower than the baseline.

| Placement | 2K prefill | 2K decode | Memory-pressure result |
|---|---:|---:|---|
| `ngl=1`, CPU MoE | 68.03 tok/s | 19.55 tok/s | 68% to 62% free; no swap-outs during the matrix |
| `ngl=2`, CPU MoE | did not finish | did not finish | 36% idle, 21% while stalled; request exceeded 2 minutes |
| `ngl=8`, CPU MoE | not run | not run | 5% free at idle; unsafe |
| `ngl=all`, CPU MoE | failed | failed | 13% to 6% free; Metal OOM/HTTP 500; about 501 MiB swap-out during the failed request |
| attention tensors forced to `MTL0` | not run | not run | 7% free and about 13.5 GiB wired at idle; unsafe |

The baseline 8K result was 65.28 tok/s prefill and 10.26 tok/s decode. Its 2K
request completed in 36.64 seconds; the `ngl=2` 2K request was stopped after it
exceeded two minutes without completing. Baseline RSS after the 2K request was
7,406,416 KiB.

The full-offload failure was explicit
`kIOGPUCommandBufferCallbackErrorOutOfMemory`. The result is specific to this
16 GiB unified-memory machine: the diagram's separate-VRAM premise does not
hold here because CPU and GPU compete for the same physical memory, and Metal
buffers are wired. llama.cpp applies tensor overrides after normal layer
assignment, but the attention-only override was even more memory-expensive than
the normal allocator.

Raw baseline throughput rows are in
[`../../logs/qwen36-split-ngl1.jsonl`](../../logs/qwen36-split-ngl1.jsonl).
