# Choosing a model

All profiles are local, single-server, multimodal llama.cpp configurations for
the same MacBook Pro M5/16 GB baseline. They use port `8081` by default, so
switching model means stopping the current process and starting another one.
This is intentional: unified memory is the limiting resource, and keeping two
large multimodal models resident would make the machine unreliable.

| Profile | Use it when | Main tradeoff | Default speculation | Full profile |
|---|---|---|---|---|
| Gemma 4 12B | You want the default balanced Gemma profile | Larger model and projector consume meaningful memory | External MTP | [Gemma 4 12B](model-profiles/gemma4-12b.md) |
| Gemma 4 E4B | You want Gemma behavior with a lighter model | Less capacity than 12B | External MTP | [Gemma 4 E4B](model-profiles/gemma4-e4b.md) |
| Qwen 3.5 4B | Interactive coding and fast iteration | Lowest Qwen capacity | MTP; n-gram available | [Qwen 3.5 4B](model-profiles/qwen35-4b.md) |
| Qwen 3.5 9B | Better Qwen output without 35B MoE cost | More memory and slower decode than 4B | MTP; n-gram available | [Qwen 3.5 9B](model-profiles/qwen35-9b.md) |
| Qwen 3.6 35B A3B | Maximum local model capability and MoE reasoning | Tightest 16 GB margin and CPU-MoE cost | Disabled | [Qwen 3.6 35B](model-profiles/qwen36-35b.md) |

## Selection workflow

Start with `qwen35-4b` when validating a toolchain, prompt format or vision
request quickly. Move to `qwen35-9b` when the task benefits from a stronger
Qwen profile. Choose Gemma for its model family and external MTP behavior.
Reserve `qwen36-35b` for tasks where the larger MoE model is worth slower,
memory-sensitive operation.

The names describe files, not a promise of output quality. Benchmark the exact
prompt lengths, images and tool calls used in production; rankings change by
workload.

## Multimodality and persistence

Every profile loads a BF16 `mmproj` by default. The projectors are not optional
in the intended operating mode. Upstream llama.cpp disables disk slot
save/restore when a multimodal projector is loaded, so this repository omits
that API instead of exposing a command that fails with HTTP 501.

Prompt cache, context checkpoints and n-gram lookup caches are separate
mechanisms. They may remain in memory or in the Qwen lookup file, but none is a
resumable conversation snapshot. See [parameter decisions](parameters.md).

## Adding a profile

Copy the closest config and retain the contract used by `server/start.sh`:

1. Define model identity, paths, alias, port and runtime defaults.
2. Implement `pre_launch`, `build_extra_args` and `build_spec_args`.
3. Emit one argument per line from the two builder functions. The launcher reads
   them into Bash arrays, preserving quoting.
4. Add a detailed profile document under `docs/model-profiles/`.
5. Run lint, tests and a benchmark against the actual server before publishing.

The launcher validates files and server health; it cannot prove that arbitrary
GGUF weights and a projector are semantically compatible. That remains the
profile author's responsibility.
