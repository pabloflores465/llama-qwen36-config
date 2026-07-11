# Architecture and lifecycle

This repository runs exactly one local `llama-server`. Model configs are data
plus three small hooks; lifecycle policy remains in the shared server scripts.

```text
config/<model>.conf -> server/start.sh -> llama-server HTTP API
                              |                |-- slot.sh
                              |                `-- bench/bench.sh
                              |-- logs/<model>.log
                              |-- models/.run/server.state
                              `-- .pi/settings.json
```

## Configuration contract

Every config defines paths, runtime variables and these functions:

- `pre_launch`: validates or prepares model-specific resources.
- `build_extra_args`: emits one common-command argument per line.
- `build_spec_args`: emits speculative-decoding arguments per line.

Arguments are read into Bash arrays, preserving spaces and preventing accidental
shell evaluation. Config files are trusted shell code and must not come from an
untrusted source.

## Transactional startup

Startup selects and sources the model before choosing `PORT_DEFAULT`. It removes
stale metadata, validates assets, starts the process and waits for `/health`.
Only then does it atomically publish `server.state` and focus Pi on that URL. A
failed start terminates its child, removes runtime metadata and restores Pi's
canonical `http://127.0.0.1:8081` endpoint.

Foreground mode uses the same child, health check and state publication path as
background mode. It then waits and forwards INT/TERM to the server.

## Safe shutdown

Shutdown only signals the recorded PID if its command contains `llama-server`
and that PID owns the recorded listening port. It never kills an arbitrary
listener merely because stale state mentions its port.

## State consumers

`slot.sh` and `bench.sh` consume `server.state`. The benchmark additionally
checks `/health` and verifies that `/v1/models` contains the recorded alias.
Runtime state and personal Pi settings are intentionally ignored by Git.
