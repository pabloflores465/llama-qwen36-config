# Qwen 3.6 full-GPU built-in MTP experiment

Tested on the 16 GiB M5 with llama.cpp b9910 and the IQ2_M
Qwen3.6-35B-A3B model. Both runs used a configured 65,536-token context, full
weight offload, host-resident Q4 K/V, batch 2048, microbatch 64, one slot, no
projector, no prompt RAM cache and no context checkpoints. MTP used the model's
built-in head with a maximum draft of two tokens and Q4 draft K/V.

| Populated prompt | Mode | Prefill | Decode | Wall time | RSS after request |
|---:|---|---:|---:|---:|---:|
| 2,047 | none | 333.22 tok/s | 16.51 tok/s | 21.68 s | 3.16 GiB |
| 2,047 | MTP | 251.01 tok/s | 18.94 tok/s | 21.69 s | 5.64 GiB |
| 16,383 | none | 252.92 tok/s | 13.75 tok/s | 74.12 s | 3.21 GiB |
| 16,383 | MTP | 210.47 tok/s | 13.14 tok/s | 87.61 s | 5.52 GiB |

At 2K, MTP improved decode by 14.7% but reduced prefill by 24.7%, leaving total
request time unchanged. At 16K it reduced prefill by 16.8%, reduced decode by
4.4%, and increased total time by 18.2%. Draft acceptance was 100% in both MTP
requests (170/170 and 84/84), so this synthetic repetitive workload was a
best-case acceptance test rather than an adversarial one.

Both modes operated at only 4–6% system memory free with roughly 13.4 GiB of
wired pages. MTP increased measured process RSS by approximately 2.3–2.5 GiB.
Global VM counters also showed about 4.8x as many compression operations during
the 2K request and 4.5x during the 16K request. Swap-out traffic was roughly
179 MiB / 419 MiB without MTP and 258 MiB / 407 MiB with MTP for the 2K / 16K
requests respectively. These system-wide counters include other macOS activity,
but consistently indicate that both full-GPU modes have almost no safety margin.

Built-in MTP is therefore supported by the full-GPU profile but remains disabled
by default. Its short-context decode gain does not compensate for prefill and
memory-pressure costs on this machine.

Raw rows:

- [`../../logs/qwen36-gpu-full-none-64k.jsonl`](../../logs/qwen36-gpu-full-none-64k.jsonl)
- [`../../logs/qwen36-gpu-full-mtp-64k.jsonl`](../../logs/qwen36-gpu-full-mtp-64k.jsonl)
