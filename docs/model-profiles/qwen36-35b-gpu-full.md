# Qwen 3.6 35B A3B — full GPU experiment

Config: [`config/qwen36-35b-gpu-full.conf`](../../config/qwen36-35b-gpu-full.conf)

This experimental profile attempts full Metal placement of the IQ2_M weights on
the 16 GiB M5. It disables the multimodal projector and MTP, uses a 65,536-token
context, reduces the microbatch to 64, and keeps the Q4 K/V cache on the host.
The normal [`qwen36-35b`](qwen36-35b.md) CPU-MoE profile remains unchanged.

The local llama.cpp estimator reports 10,988 MiB for weights and 66 MiB for
compute on Metal. Moving the 422 MiB context allocation to the host leaves about
1,070 MiB below the reported 12,124 MiB Metal limit. Runtime allocations can
still exceed the estimate, so close other applications before starting it.

```bash
./server/start.sh qwen36-35b-gpu-full
```

Stop it normally with `./server/stop.sh`. If Metal still reports out-of-memory,
use the normal profile; do not enable the projector or increase the microbatch.
Built-in MTP can be enabled experimentally with `SPEC_MODE=mtp`; it remains off
by default until its measured speed and memory cost justify the extra work.
