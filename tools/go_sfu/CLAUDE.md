# Go/Pion SFU

The group call test mode uses a Go-based SFU (Selective Forwarding Unit) built with [Pion WebRTC](https://github.com/pion/webrtc), linked into the C++ `tgcalls_cli` binary via CGo.

## Build Integration
- `MODULE.bazel` — `rules_go` 0.60.0 + Go SDK 1.24.2 + `gazelle` 0.43.0; Pion dependencies managed via `go_deps` Gazelle extension
- `tools/go_sfu/BUILD` — `go_binary` with `linkmode = "c-archive"` produces a static archive + CGo header, exposes `CcInfo` to C++ targets
- `tools/go_sfu/go.mod` / `go.sum` — Pion dependency declarations (pion/ice, pion/dtls, pion/srtp, pion/sctp)
- `tools/tgcalls_cli/BUILD` — depends on `//tools/go_sfu` to link the Go archive
- The CGo-generated header is included as `#include "tools/go_sfu/go_sfu.h"` in C++ code

## How It Works
The `go_binary` with `linkmode = "c-archive"` compiles Go code (including the Go runtime) into a `.a` static archive. Functions annotated with `//export` in Go become C-callable symbols. Bazel's `rules_go` automatically provides `CcInfo`, so `cc_binary` targets can depend on the Go archive via `deps` — no manual linkopts needed.

The Go runtime (GC, goroutine scheduler) runs inside the C++ process. This adds ~10MB memory overhead. `GoSfu_Init()` must be called before any other Go functions.

## Key Files
- `tools/go_sfu/sfu.go` — SFU core: participant registry, join/leave/response flow, audio+video RTP forwarding, SSRC registry (audio/video/video-rtx with layer index), Colibri `ReceiverVideoConstraints`/`SenderVideoConstraints` handling, PLI/FIR forwarding, `ActiveAudioSsrcs`/`ActiveVideoSsrcs` broadcasting, `//export` C bindings (`GoSfu_Init`, `GoSfu_Create`, `GoSfu_Destroy`, `GoSfu_Join`, `GoSfu_Leave`, `GoSfu_QuerySsrc`, `GoSfu_QueryVideoSsrcs`, `GoSfu_Free`, `GoSfu_Shutdown`)
- `tools/go_sfu/participant.go` — per-participant transport stack (ICE agent, DTLS conn, SRTP session, SRTCP contexts for manual RTCP decrypt/encrypt, SCTP association, data channel send/receive, per-receiver video layer selection)
- `tools/go_sfu/mux.go` — packet demuxer: three-way split of ICE traffic into DTLS handshake, SRTP (RTP), and SRTCP (RTCP) channels per RFC 7983 + RFC 5761
- `tools/go_sfu/go.mod` / `go.sum` — Go module with Pion dependencies
- `tools/tgcalls_cli/group_mode.cpp` — C++ side that drives the group join flow and calls into Go SFU
- `tools/tgcalls_cli/group_mode.h` — header for group mode entry point
- `tools/tgcalls_cli/group_participant.h/.cpp` — shared participant lifecycle helpers (`createParticipant`, `stopParticipant`, `validateGroupState`, `printGroupSummary`), `ParticipantState` struct, audio helpers
- `tools/tgcalls_cli/group_churn_mode.h/.cpp` — group-churn stress test: base group + rapid join/leave cycling

## SFU Bandwidth Adaptation

The SFU implements REMB-based bandwidth-adaptive simulcast layer selection for video. Per receiver, it maintains an EWMA-smoothed bandwidth estimate from REMB RTCP feedback and uses a `LayerSelector` state machine per (receiver, sender) pair to decide which simulcast layer to forward.

### State Machine
- **STABLE**: forwarding current layer. Checks for upswitch opportunity (REMB > threshold × 1.2) or downswitch need (REMB < threshold × 0.7).
- **PROBING_UP**: ramping RTX padding from 0 to the gap between current and target layer bitrate over 2 seconds. Aborts if REMB drops; succeeds if REMB sustains.
- **GRACE_DOWN**: REMB below downswitch threshold. Waits 500ms, then downswitches if not recovered. 5-second cooldown after any switch.

### Layer Thresholds
| Layer | Nominal | Upswitch When | Downswitch When |
|-------|---------|--------------|-----------------|
| 0 | 60 kbps | (start) | (never) |
| 1 | 110 kbps | BW > 132 kbps | BW < 77 kbps |
| 2 | 900 kbps | BW > 1,080 kbps | BW < 630 kbps |

### Layer Selection and SSRC Rewriting
The SFU forwards exactly one simulcast layer per (receiver, sender) pair. Before `ReceiverVideoConstraints` arrives, the SFU uses `requestedLayer` as the cap and forwards at `maxActiveLayer` (the highest layer the encoder actually produces). After constraints arrive, `ensureLayerSelector` sets `selectedLayer` clamped to `maxActiveLayer`.

When forwarding a non-base layer, the SFU rewrites the RTP SSRC to the primary (layer 0) SSRC. This is necessary because `IncomingVideoChannel` in CustomImpl attaches its `VideoSinkImpl` to `_mainVideoSsrc` (the first SSRC in the SIM group, i.e., layer 0). Without SSRC rewriting, packets from higher layers are delivered to the wrong receive stream and never decoded. RTX SSRCs are similarly rewritten to the layer 0 FID SSRC.

### Testing on Localhost
Use `--network-scenario step-down-up` to exercise the full adaptation path via per-client network simulation (replaces the old REMB-override `--bw-scenario`).

```bash
# Network scenario test (30s, 4 phases: uncapped → 80k egress → 200k → uncapped)
./bazel-bin/tools/tgcalls_cli/tgcalls_cli --mode group --participants 2 --video --duration 30 --network-scenario step-down-up
```

Unit tests drive the `LayerSelector` state machine directly via mocked callbacks. Run from `tools/go_sfu/`:

```bash
go test -run TestLayerSelector -v -timeout 60s
```

Covers upswitch L0→L1→L2, downswitch L2→L1→L0, grace-down recovery on transient dips, stale-BW idle behavior, the `OnMaxActiveLayerIncreased` fallback used when clients don't send REMB, and `maxLayer` enforcement.

### REMB-free Fallback

Real tgcalls clients negotiate `goog-remb` but use transport-cc as the primary BWE signal, so no REMB actually arrives at the SFU. This means the REMB-driven state machine never enters `PROBING_UP` in live runs. `LayerSelector.OnMaxActiveLayerIncreased(maxActive)` is the fallback: when the sender starts producing a higher simulcast layer than previously seen AND the BW estimate is stale, the SFU immediately upshifts to the highest available layer (clamped by `maxLayer`). Called from `sfu.go`'s packet-forwarding path whenever `maxActiveLayer[senderID]` is bumped.

### Key Files
- `tools/go_sfu/bandwidth.go` — `BandwidthEstimator`, `LayerSelector`, `RtxRingBuffer`, `OnMaxActiveLayerIncreased`
- `tools/go_sfu/bandwidth_test.go` — unit tests for `LayerSelector` up/down transitions
- `tools/go_sfu/participant.go` — REMB parsing in `readRTCPLoop()`, `selectedLayers`
- `tools/go_sfu/sfu.go` — layer-filtered forwarding, `ensureLayerSelector`, SSRC rewriting, `maxActiveLayer` tracking

## SFU Transport-CC Feedback

The SFU generates RTCP transport-cc feedback (type 205, FMT 15) per sender every 100ms. This provides the sender's GCC (Google Congestion Control) with packet arrival data, enabling BWE ramp-up so the encoder produces higher simulcast layers.

The feedback reflects actual (or simulated) packet arrivals — if ingress network simulation drops packets, the feedback reports them as missing, causing the sender's GCC to reduce bitrate.

### How It Works
1. Each incoming RTP packet is parsed for the transport-wide sequence number (header extension ID 3, one-byte RFC 5285 format)
2. `TransportCCGenerator.RecordArrival(twccSeq)` records the arrival time
3. Every 100ms, `emitFeedback()` builds an `rtcp.TransportLayerCC` packet with `PacketChunks` (run-length or status-vector encoding) and `RecvDeltas` (250µs units)
4. The feedback is marshalled, encrypted via SRTCP, and sent to the sender
5. The sender's `Call::Receiver::DeliverRtcpPacket()` feeds it to the GCC via `GroupNetworkManager::OnRtcpPacketReceived_n` → `_call->Receiver()->DeliverRtcpPacket()`

### Current Status
Transport-cc feedback is working: the SFU records ~60-70 arrivals per first 100ms tick, generates feedback packets (32-128 bytes), and the sender receives them. The GCC ramps from the 400kbps start bitrate to produce layer 1 (640x360). Full ramp to layer 2 (1280x720, needs ~1Mbps) requires further investigation — the GCC may need probing support or the `adjustBitratePreferences` max_bitrate_bps of 1052kbps may be a bottleneck.

### Key Files
- `tools/go_sfu/twcc.go` — `TransportCCGenerator`, `parseTWCCSeq` (RTP header extension parser)

## SFU Network Simulation

Per-client network simulation with independent ingress (from client) and egress (to client) simulators. Each direction has: delay, jitter, packet loss, and bandwidth cap (token bucket).

```bash
# Configure via CGo: GoSfu_SetNetworkParams(handle, participantID, direction, delayMs, jitterMs, dropRate, bandwidthBps)
# direction: 0 = ingress, 1 = egress

# Network scenario test (4 phases: uncapped -> 80k -> 200k -> uncapped)
./bazel-bin/tools/tgcalls_cli/tgcalls_cli --mode group --participants 2 --video --duration 30 --network-scenario step-down-up
```

### Key Files
- `tools/go_sfu/network_sim.go` — `NetworkSimulator` (token bucket, delay, jitter, drop)
- `tools/go_sfu/participant.go` — `ingressSim`, `egressSim` on each `Participant`
