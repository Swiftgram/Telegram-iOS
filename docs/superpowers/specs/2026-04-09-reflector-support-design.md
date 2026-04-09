# tgcalls CLI: UDP Reflector Mode

## Overview

Add a `--mode reflector` option to the tgcalls CLI test tool, routing both call instances through a real Telegram UDP reflector instead of direct P2P loopback.

## CLI Interface

- `--mode p2p` — current behavior (direct P2P loopback, no servers)
- `--mode reflector` — route through a real Telegram UDP reflector
- `--mode` is **required**. Exit with usage error if missing.
- `--reflector host:port` — specifies the reflector address. **Required** when `--mode reflector`. Error if missing in reflector mode or if provided with `--mode p2p`.
- `--duration` and `--quiet` are unchanged.

## Reflector Configuration

When `--mode reflector`:

### Peer Tag Generation

Generate 16 random bytes. Copy to make two tags:
- Caller tag: byte 0 = `0x00`
- Callee tag: byte 0 = `0x01`

### RtcServer Setup

Each instance gets one `RtcServer` entry with its respective peer tag:

| Field      | Value                                          |
|------------|------------------------------------------------|
| `id`       | `1`                                            |
| `host`     | from `--reflector` argument                    |
| `port`     | from `--reflector` argument                    |
| `login`    | `"reflector"`                                  |
| `password` | hex-encoded 16-byte peer tag (differs by side) |
| `isTurn`   | `true`                                         |
| `isTcp`    | `false`                                        |

### Descriptor Changes

- `config.enableP2P = false`
- `rtcServers` populated with the single reflector server
- No `customParameters` changes (standalone reflector mode is not used)

### P2P Mode

Unchanged from current behavior: `enableP2P = true`, empty `rtcServers`.

## Summary Output

Add a mode line to the call summary:

```
Mode:              reflector (91.108.13.2:596)
```

or:

```
Mode:              p2p
```

No other output changes. The existing audio validation (440Hz sine, non-silence detection) remains the success criterion for both modes.
