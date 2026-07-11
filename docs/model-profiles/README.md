# Model profile reference

Each file in this section maps one `config/*.conf` profile to its actual model
files, runtime defaults, model-specific flags and tradeoffs. Read the common
[parameter reference](../parameters.md) first; these pages explain why a profile
uses one allowed value instead of another.

| Profile | Config | Detail |
|---|---|---|
| Gemma 4 12B QAT | [`config/gemma4-12b.conf`](../../config/gemma4-12b.conf) | [Gemma 4 12B](gemma4-12b.md) |
| Gemma 4 E4B QAT | [`config/gemma4-e4b.conf`](../../config/gemma4-e4b.conf) | [Gemma 4 E4B](gemma4-e4b.md) |
| Qwen 3.5 4B MTP | [`config/qwen35-4b.conf`](../../config/qwen35-4b.conf) | [Qwen 3.5 4B](qwen35-4b.md) |
| Qwen 3.5 9B MTP | [`config/qwen35-9b.conf`](../../config/qwen35-9b.conf) | [Qwen 3.5 9B](qwen35-9b.md) |
| Qwen 3.6 35B A3B MTP | [`config/qwen36-35b.conf`](../../config/qwen36-35b.conf) | [Qwen 3.6 35B](qwen36-35b.md) |

All paths are defaults, not downloaded assets. The launcher fails early with a
clear path error if a required GGUF is absent.
