# GroupInstanceReferenceImpl: Reactive Remote-Audio-SSRC Discovery

**Date:** 2026-05-01
**Status:** Approved (design only — no implementation yet)
**Scope:** `submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp` and adjacent test wiring.

## Problem

`GroupInstanceReferenceImpl` (PeerConnection-based group call client) currently learns about remote audio SSRCs **only** from a `colibriClass=ActiveAudioSsrcs` data-channel message broadcast by the test-bench Pion SFU (`tgcalls/tools/go_sfu/sfu.go`). The real Telegram SFU does not send that message — `GroupInstanceCustomImpl::receiveDataChannelMessage` only handles `SenderVideoConstraints` and `DebugMessage`. CustomImpl discovers SSRCs reactively from raw RTP via `GroupNetworkManager` → `receiveUnknownSsrcPacket` → `maybeRequestUnknownSsrc` → `_requestMediaChannelDescriptions`. ReferenceImpl has no equivalent path; in real calls every remote audio packet is silently dropped (or routed to mid=0's unsignaled handler with no application visibility).

The fix must:
- Surface every previously-unseen remote audio SSRC to ReferenceImpl's internal logic, ideally on the first frame.
- Drive the addition of a recvonly audio transceiver for that SSRC.
- Match CustomImpl's app-facing contract — the application sees the same `_requestMediaChannelDescriptions(ssrcs, completion)` callback it already implements.
- Use a single discovery mechanism in both real and test environments (the test SFU's `ActiveAudioSsrcs` broadcast becomes obsolete and is removed; see "Removing `ActiveAudioSsrcs`" below).

## Approach: one `GRAudioFrameTransformer` installed on every audio receiver

WebRTC exposes `RtpReceiverInterface::SetDepacketizerToDecoderFrameTransformer(FrameTransformerInterface*)`. The transformer's `Transform(frame)` takes ownership of a `std::unique_ptr<TransformableFrameInterface>` and there is **no requirement that it call `OnTransformedFrame` synchronously** — the design is explicitly async. The transformer can hold the frame for arbitrarily long; the audio pipeline simply waits.

We install **the same `GRAudioFrameTransformer` instance on every audio receiver** in this `GroupInstanceReferenceInternal`:

- **mid=0 (sendrecv outgoing audio)** — explicitly via `_outgoingAudioTransceiver->receiver()->SetDepacketizerToDecoderFrameTransformer(_audioFrameTransformer)` in `start()`. This lands as both the per-receiver transformer and (because mid=0's receive side has `signaled_ssrc=nullopt`) the channel's `unsignaled_frame_transformer_` — meaning any unsignaled stream created later for an unknown SSRC also gets it.
- **Each recvonly audio transceiver** (added by the discovery flow) — explicitly via the same call when the transceiver is added in `renegotiate()`. This is structurally required for the upcoming e2e-decrypt fix (every receiver needs the decrypt hook); attaching it now too is free and removes our reliance on stream-promotion implicitly carrying the transformer along.

The transformer carries the per-SSRC state machine (described below). It also carries a `decryptHook` callable (initially null) that the e2e PR will wire to `descriptor.e2eEncryptDecrypt`. Today the hook just passes the frame through unchanged; tomorrow it decrypts before `OnTransformedFrame`.

### Why install on every receiver explicitly

If we relied solely on `unsignaled_frame_transformer_`, the transformer would be carried onto a recvonly transceiver only via the stream-promotion path (`webrtc_voice_engine.cc:2258-2266`: `MaybeDeregisterUnsignaledRecvStream` keeps the stream object intact, transformer attached). That's correct *today* but it's an internal-WebRTC behavior we'd be pinning to. Once we explicitly attach to each recvonly receiver we own the lifecycle: the transformer is on the stream because we put it there, regardless of how WebRTC's voice engine handles the unsignaled→signaled transition.

For the buffer flush specifically: the buffered frames were captured while the SSRC was on mid=0's unsignaled-fallback path. When we later install the transformer on the recvonly receiver R' for the same SSRC, the channel's stream (now promoted in place) keeps the same transformer reference (same instance, same pointer) — so `releaseSsrc` flushes through `_perSsrcSinks[ssrc]` (the sink callback WebRTC registered when the stream first appeared) and frames land in that one stream's decoder.

### Tap behavior

For each SSRC the transformer maintains an `Entry { state, buffer, firstFrameTimeMs }` with `state ∈ { kBuffering, kDrained }`.

`Transform(frame)` (worker thread):
1. Acquire the mutex.
2. Look up the entry for `frame->GetSsrc()`.
3. If absent and we're below `kMaxConcurrentBufferedSsrcs`: insert with `kBuffering` state, post `_onNewSsrc(ssrc)` to the media thread (outside the lock), buffer the frame.
4. If `kBuffering`: append to buffer (drop oldest if `buffer.size() >= kMaxBufferedFramesPerSsrc`).
5. If `kDrained`: release the lock, then call `OnTransformedFrame(std::move(frame))`. Live audio flows through.

`releaseSsrc(uint32_t ssrc)` (media thread, called from `onRenegotiationComplete`):
1. Acquire the mutex.
2. Locate the entry; if absent or already `kDrained`, return.
3. Move the deque out, mark `state = kDrained`, release the mutex.
4. Iterate the moved deque calling `OnTransformedFrame(std::move(frame))` on each. Performed outside the lock to avoid re-entrant deadlocks.

The order of operations matters: marking `kDrained` *before* releasing the lock guarantees that any concurrent `Transform()` either (a) sees `kBuffering` and buffers — but its frame is lost because we already drained the FIFO, or (b) sees `kDrained` and passes through. Case (a) is a real one-frame-loss race window. We accept it: at 20 ms Opus that's a single packet of audio, inaudible, and overwhelmingly unlikely (the window is the few microseconds between unlocking and starting the drain loop).

### Failure mode

If `releaseSsrc(X)` is not called within `kSsrcDiscoveryTimeoutMs = 1000` ms (renegotiation failed or app declined the SSRC), an in-line eviction inside `Transform()` drops the buffer and **leaves the entry in `kBuffering` with empty FIFO**. Subsequent frames continue to attempt to buffer (and immediately drop on the FIFO cap = 0 / re-eviction), so the participant remains silent until the entry is cleared. Acceptable — the same outcome as the pure-drop alternative would have produced.

### Net behavior

- **Audible continuity for new participants.** Buffered frames flush into the same stream that carries future audio. NetEQ sees the buffered burst as one large jitter-buffer fill followed by normal-paced packets — same shape as recovering from a network glitch. May produce a brief audible artifact during the burst (NetEQ may accelerate or reorder) but no silence.
- **No orphaned `AudioReceiveStream`.** Stream is promoted in place; one stream per SSRC.
- **Tap stays in the live path.** Per-frame: one mutex, one map lookup, one `OnTransformedFrame`. Hot but cheap.

CustomImpl already uses `FrameTransformer` (for E2E encryption) — the pattern is established in this codebase. Pass-through transformers also work in WebRTC (the `OnTransformedFrame` callback is the only contract).

### Why not the alternatives

- **`OnTrack` for unsignaled audio:** PeerConnection's "default" handler creates one default track. Multi-SSRC behavior is murky; fragile.
- **`PeerConnection::GetStats()` polling:** Works but adds 100–250 ms of discovery latency per new participant (audio drops during the window) and the stats walk is non-trivial.
- **Tap on a custom socket factory:** Requires re-implementing SRTP decrypt and RTP parsing. Too invasive.

## Components

```
                                ┌────────────────────────────┐
   incoming RTP (any SSRC) ───▶ │  PeerConnection BUNDLE     │
                                │  demuxer (SSRC-keyed)      │
                                └─────────────┬──────────────┘
                                              │
                          ┌───────────────────┼─────────────────────┐
                          │                   │                     │
                  signaled SSRC X     signaled SSRC Y     unknown / catch-all
                  (recvonly mid=N1)   (recvonly mid=N2)   (sendrecv mid=0)
                          │                   │                     │
                          ▼                   ▼                     ▼
                  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐
                  │ AudioTrack   │   │ AudioTrack   │   │ GRSsrcTapTransformer │
                  │ + level sink │   │ + level sink │   │ (Transform → notify  │
                  └──────────────┘   └──────────────┘   │  + OnTransformedFrame)│
                                                       └──────────┬───────────┘
                                                                  │ (worker thread)
                                                                  │
                                                                  ▼
                                                       PostTask to media thread
                                                                  │
                                                                  ▼
                                                       handleDiscoveredAudioSsrc(ssrc)
                                                                  │
                                                                  ▼
                                                       (existing) renegotiate() +
                                                       _requestMediaChannelDescriptions
```

### `GRAudioFrameTransformer` (new, anonymous-namespace class in `GroupInstanceReferenceImpl.cpp`)

```cpp
class GRAudioFrameTransformer : public webrtc::FrameTransformerInterface {
public:
    using SsrcCallback = std::function<void(uint32_t ssrc)>;
    // Hook for the future e2e-decrypt fix. Called per frame on the worker
    // thread before OnTransformedFrame. Today: identity (passes the frame
    // through unchanged). The e2e PR will assign it to a closure that
    // unwraps the descriptor.e2eEncryptDecrypt envelope.
    using DecryptHook = std::function<bool(webrtc::TransformableFrameInterface&)>;

    GRAudioFrameTransformer(SsrcCallback onNewSsrc,
                            DecryptHook decrypt,  // may be nullptr
                            rtc::Thread* mediaThread);

    // Called from ReferenceImpl on the media thread after onRenegotiationComplete
    // confirms a recvonly transceiver now owns `ssrc`. Drains the per-SSRC
    // FIFO into OnTransformedFrame in arrival order; subsequent frames for
    // `ssrc` flow through unchanged (kDrained = live passthrough).
    void releaseSsrc(uint32_t ssrc);

    // FrameTransformerInterface
    void Transform(std::unique_ptr<webrtc::TransformableFrameInterface> frame) override;
    void RegisterTransformedFrameCallback(rtc::scoped_refptr<webrtc::TransformedFrameCallback>) override;
    void RegisterTransformedFrameSinkCallback(rtc::scoped_refptr<webrtc::TransformedFrameCallback>, uint32_t ssrc) override;
    void UnregisterTransformedFrameCallback() override;
    void UnregisterTransformedFrameSinkCallback(uint32_t ssrc) override;

private:
    enum class SsrcState { kBuffering, kDrained };

    struct Entry {
        SsrcState state = SsrcState::kBuffering;
        std::deque<std::unique_ptr<webrtc::TransformableFrameInterface>> buffer;
        int64_t firstFrameTimeMs = 0; // for timeout eviction
    };

    void evictExpired_n() RTC_EXCLUSIVE_LOCKS_REQUIRED(_mu); // called inside Transform

    SsrcCallback _onNewSsrc;
    rtc::Thread* _mediaThread; // used only as identity for assertions

    webrtc::Mutex _mu;
    rtc::scoped_refptr<webrtc::TransformedFrameCallback> _broadcastSink RTC_GUARDED_BY(_mu);
    std::map<uint32_t, rtc::scoped_refptr<webrtc::TransformedFrameCallback>> _perSsrcSinks RTC_GUARDED_BY(_mu);
    std::map<uint32_t, Entry> _entries RTC_GUARDED_BY(_mu);

    static constexpr int64_t kSsrcDiscoveryTimeoutMs = 1000;
    static constexpr size_t kMaxBufferedFramesPerSsrc = 60;        // ~1.2s at 20ms Opus
    static constexpr size_t kMaxConcurrentBufferedSsrcs = 64;       // upper bound on memory
};
```

#### `Transform` (worker thread)

1. `ssrc = frame->GetSsrc()`. Acquire `_mu`.
2. `evictExpired_n()` — walk `_entries`; for any whose `firstFrameTimeMs` is older than `kSsrcDiscoveryTimeoutMs` and still `kBuffering`, clear the buffer (entry stays so we don't re-notify; subsequent frames re-evict and stay silent until the entry is removed by an explicit application action — acceptable failure mode).
3. Look up the entry for `ssrc`:
   - **Not present and `_entries.size() >= kMaxConcurrentBufferedSsrcs`** → drop frame, no notify (overflow protection against pathological SFU behavior).
   - **Not present otherwise** → insert `Entry{ kBuffering, {}, now() }`, push frame, **release lock**, invoke `_onNewSsrc(ssrc)` (which posts to media thread → `handleDiscoveredAudioSsrc(ssrc)`).
   - **Present and `kBuffering`**:
     - If `entry.buffer.size() >= kMaxBufferedFramesPerSsrc` → drop the oldest buffered frame (FIFO bounded).
     - Push `std::move(frame)` to the back of `entry.buffer`.
   - **Present and `kDrained`** → take a local copy of the appropriate sink callback (per-SSRC if registered, else broadcast), **release lock**, call `sink->OnTransformedFrame(std::move(frame))`. This is the live-audio path after `releaseSsrc` has fired.

The mutex is held only across the lookup and entry/buffer mutation. Both branches that emit through `OnTransformedFrame` (`kDrained` in `Transform`, and `releaseSsrc`) drop the lock before the call to avoid re-entrant deadlocks — WebRTC may synchronously schedule decoder work in `OnTransformedFrame` that calls back into related machinery.

#### `releaseSsrc(uint32_t ssrc)` (media thread)

1. Acquire `_mu`. Locate the entry; if missing or already `kDrained`, return.
2. Find the appropriate sink callback: per-SSRC if registered, else broadcast.
3. Mark `entry.state = kDrained` and `std::move` the deque out. **Marking `kDrained` before releasing the lock** is what guarantees no concurrent `Transform()` can buffer a frame that we then fail to flush.
4. Release `_mu`. Iterate the moved deque calling `sink->OnTransformedFrame(std::move(frame))` on each.

#### `Register*` / `Unregister*`

Store the callbacks under `_mu`. The per-SSRC `RegisterTransformedFrameSinkCallback` is invoked by WebRTC the first time a new SSRC arrives at this transformer; we hold it so `releaseSsrc` can dispatch through it. `Unregister*` clears.

### Hook points in `GroupInstanceReferenceInternal`

In `start()`, after `_outgoingAudioTransceiver` is created (mid=0):

```cpp
auto weak = std::weak_ptr<GroupInstanceReferenceInternal>(shared_from_this());
auto threads = _threads;
_audioFrameTransformer = rtc::make_ref_counted<GRAudioFrameTransformer>(
    /*onNewSsrc=*/[weak, threads](uint32_t ssrc) {
        threads->getMediaThread()->PostTask([weak, ssrc]() {
            if (auto strong = weak.lock()) {
                strong->handleDiscoveredAudioSsrc(ssrc);
            }
        });
    },
    /*decrypt=*/nullptr,                  // wired in the e2e PR
    /*mediaThread=*/_threads->getMediaThread());
_outgoingAudioTransceiver->receiver()->SetDepacketizerToDecoderFrameTransformer(
    _audioFrameTransformer);
```

In `renegotiate()`, immediately after `_peerConnection->AddTransceiver(MEDIA_TYPE_AUDIO, recvonly)` succeeds for an SSRC discovered through the tap, attach the same transformer to the new receiver:

```cpp
auto result = _peerConnection->AddTransceiver(cricket::MEDIA_TYPE_AUDIO, init);
if (result.ok()) {
    info.transceiver = result.value();
    info.transceiver->receiver()
        ->SetDepacketizerToDecoderFrameTransformer(_audioFrameTransformer);
}
```

In `onRenegotiationComplete()`, after `wireRemoteAudioLevelSinks()` runs, release any SSRCs whose recvonly transceiver just became active:

```cpp
if (_audioFrameTransformer) {
    for (auto& [ssrc, info] : _remoteSsrcs) {
        if (info.transceiver && info.transceiver->mid().has_value()) {
            // Idempotent: releaseSsrc no-ops on entries already drained.
            _audioFrameTransformer->releaseSsrc(ssrc);
        }
    }
}
```

### `handleDiscoveredAudioSsrc(uint32_t ssrc)` (new, on media thread)

This is the **only** entry point for adding a remote audio SSRC. It accumulates the SSRC into `_remoteSsrcs` and **schedules** a single coalesced renegotiation rather than firing one immediately:

```cpp
void handleDiscoveredAudioSsrc(uint32_t ssrc) {
    if (ssrc == 0) return;
    if (ssrc == _outgoingSsrc) return;          // our own
    if (_remoteSsrcs.count(ssrc) > 0) return;   // already known

    std::string mid = std::to_string(_nextMid++);
    RemoteSsrcInfo info;
    info.mid = mid;
    _remoteSsrcs.emplace(ssrc, std::move(info));

    if (_requestMediaChannelDescriptions) {
        _requestMediaChannelDescriptions({ssrc}, [](auto&&) { /* fire-and-forget */ });
    }
    scheduleDiscoveryRenegotiation();
}
```

### Removing `ActiveAudioSsrcs`

With the tap as the canonical discovery path, the test SFU's `ActiveAudioSsrcs` broadcast becomes redundant — and continuing to ship it would mean test runs exercise a code path that doesn't exist in production. Three deletions:

1. `tools/go_sfu/sfu.go` — remove the `colibriClass=ActiveAudioSsrcs` broadcast (the message construction at `sfu.go:987` and any per-participant-join trigger that emits it). Remove the `ColibriClass`/`Ssrcs` JSON struct used solely for this purpose.
2. `GroupInstanceReferenceImpl.cpp` — delete `handleActiveAudioSsrcs(json)` and the `if (colibriClass == "ActiveAudioSsrcs") { ... }` dispatch in `onDataChannelMessage`. The dispatch becomes "forward to app callback if set" only (currently forwards regardless, so just drop the colibri branch).
3. `tools/cli/group_participant.cpp` — no change required. The CLI already only reacts to `ActiveVideoSsrcs` in its `dataChannelMessageReceived`; `ActiveAudioSsrcs` was never observed by the test app, only consumed internally by ReferenceImpl.

Verification that removal is safe: `grep -r ActiveAudioSsrcs` across the repo currently returns hits only in (1) the SFU emitter, (2) the ReferenceImpl handler we're deleting, and (3) documentation/CLAUDE.md files (which we update as part of the change). CustomImpl never references it; iOS app code never references it; the test CLI never references it.

Removed-SSRC handling: the deleted `handleActiveAudioSsrcs` also processed *removals* (SFU told us a participant left). After deletion, ReferenceImpl no longer reacts to participant departures via the data channel. This matches CustomImpl's behavior — CustomImpl also has no remove path; SSRCs simply go silent and the application removes them from the participant list via MTProto. Recvonly transceivers stay in the SDP indefinitely, which is a small per-call leak but not a correctness issue. (If this proves to be a problem in long-running calls, a future change can add a "remove if no audio for N seconds" sweep.)

### `scheduleDiscoveryRenegotiation()` — debounce window

A 250 ms delayed task on the media thread coalesces a burst of discoveries into one renegotiation. The existing `renegotiate()` already iterates `_remoteSsrcs` and adds a recvonly transceiver for any entry that doesn't have one yet, so all SSRCs accumulated during the delay window are picked up in a single offer/answer cycle.

```cpp
static constexpr int kDiscoveryRenegotiationDelayMs = 250;

void scheduleDiscoveryRenegotiation() {
    if (_discoveryRenegotiationScheduled) return;
    _discoveryRenegotiationScheduled = true;
    auto weak = std::weak_ptr<GroupInstanceReferenceInternal>(shared_from_this());
    _threads->getMediaThread()->PostDelayedTask(
        [weak]() {
            auto strong = weak.lock();
            if (!strong) return;
            strong->_discoveryRenegotiationScheduled = false;
            strong->renegotiate();
        },
        webrtc::TimeDelta::Millis(kDiscoveryRenegotiationDelayMs));
}
```

**Layering with existing serialization.** The debounce sits on top of `renegotiate()`'s existing `_isRenegotiating` / `_pendingRenegotiation` guard. Three regimes:

1. **No renegotiation in flight when the timer fires:** `renegotiate()` runs immediately, picks up all queued SSRCs.
2. **A renegotiation is already in flight (e.g., from `setRequestedVideoChannels`):** the queued `renegotiate()` sets `_pendingRenegotiation`, runs after the in-flight cycle completes — picks up everything including the new SSRCs.
3. **More SSRCs discovered while the timer is pending:** `_discoveryRenegotiationScheduled == true` → no new task scheduled, the SSRC just lands in `_remoteSsrcs` and joins the upcoming batch.

Result: at most one discovery-sourced renegotiation per 250 ms, regardless of arrival burst size.

**Audible-gap implication.** New joiners are silent during the debounce window because their packets land in mid=0's catch-all (which still decodes them and feeds the AudioMixer for playback) but their per-receiver `GRAudioLevelSink` doesn't exist yet, so the speaking-indicator UI shows no level until the renegotiation completes (~250 ms + offer/answer round-trip). Audio is heard, the indicator just lags. Acceptable.

**Stop semantics.** On `stop()`, the queued task may still fire. The `weak_ptr` guard makes the lambda a no-op if the internal has been destroyed. The `_isRenegotiating` flag inside `renegotiate()` also bails if `_peerConnection` has been closed.

**Behavior change in test mode:** the existing `handleActiveAudioSsrcs` calls `_requestMediaChannelDescriptions` once per batch with all new SSRCs. After refactor, it issues N single-SSRC calls. This is acceptable: requests are local fire-and-forget callbacks into the app and bear no network cost in the CLI test bench. If the iOS app's implementation later turns out to be sensitive to call frequency, `handleActiveAudioSsrcs` can re-aggregate by collecting the SSRCs first and issuing one batched request after the per-SSRC `handleDiscoveredAudioSsrc` calls — but the simpler version is the starting point.

## Data flow

1. SFU starts forwarding remote audio for SSRC X (no signaling messages).
2. PeerConnection demuxes the first packet for SSRC X — no recvonly transceiver matches → routed to mid=0's catch-all receiver. The voice channel creates an unsignaled `WebRtcAudioReceiveStream` for X with our tap as the depacketizer-to-decoder transformer. `Transform(frame1)` is called.
3. Tap finds no entry for X → inserts `{ kBuffering, [frame1], now() }` → posts `_onNewSsrc(X)` to the media thread → `handleDiscoveredAudioSsrc(X)`.
4. `handleDiscoveredAudioSsrc` adds X to `_remoteSsrcs`, fires `_requestMediaChannelDescriptions({X}, ...)`, calls `scheduleDiscoveryRenegotiation()` (debounce 250 ms).
5. Subsequent packets for X arrive at the tap (state still `kBuffering`) → appended to the same FIFO (oldest dropped if `>= kMaxBufferedFramesPerSsrc`).
6. After 250 ms the debounce timer fires `renegotiate()`, which adds a recvonly transceiver bound to mid=`_nextMid++` for every entry in `_remoteSsrcs` that lacks one. `SetRemoteDescription` propagates SSRC X into the recvonly m-line; `WebRtcVoiceReceiveChannel::AddRecvStream(X)` finds X in `unsignaled_recv_ssrcs_` and **promotes** the existing stream in place (no new stream created; tap transformer remains attached).
7. `onRenegotiationComplete` runs: `wireRemoteAudioLevelSinks()` attaches a `GRAudioLevelSink` to the new recvonly receiver's track; for each SSRC whose transceiver now has a mid, ReferenceImpl calls `_ssrcTapTransformer->releaseSsrc(ssrc)`.
8. `releaseSsrc(X)` marks the entry `kDrained` under the lock, moves the FIFO out, releases the lock, and calls `OnTransformedFrame` for each buffered frame in arrival order. The promoted stream's decoder receives the burst; NetEQ buffers and plays out at natural rate.
9. Subsequent packets for X reach `Transform()`; the entry is `kDrained` → tap calls `OnTransformedFrame` directly. Live audio flows. The per-receiver `GRAudioLevelSink` (attached in step 7) reads real levels from the post-decode PCM stream.

**Failure mode (timeout).** If `releaseSsrc(X)` is not called within `kSsrcDiscoveryTimeoutMs = 1000` ms (renegotiation failed or app declined the SSRC), the in-line eviction in `Transform` clears the buffer for X. The entry stays in `kBuffering` so we don't re-notify, but no future frames are forwarded — the participant goes silent. Same outcome as the pure-drop alternative.

## Threading

- `Transform` runs on PeerConnection's worker thread. Hot path — must be cheap. Per call: one mutex acquisition, a deque push (or drop), an O(N_active_SSRCs) eviction walk that is cheap (typically 0–2 items per call). On first-sight SSRC the worker thread also posts to the media thread.
- `releaseSsrc` runs on the media thread (called from `onRenegotiationComplete`). Acquires the same mutex, moves the FIFO out under lock, then releases the lock and calls `OnTransformedFrame` outside the lock to avoid re-entrant deadlocks (WebRTC's `OnTransformedFrame` may call back into the transformer infrastructure).
- `OnTransformedFrame` itself: WebRTC's contract does not pin it to a specific thread; calling from the media thread is legal. WebRTC dispatches the actual depacketize/decode onto the worker thread internally.
- `handleDiscoveredAudioSsrc` runs on the media thread. Existing renegotiation machinery is media-thread-safe.
- Lifetime: the transformer is owned by `_ssrcTapTransformer` (member, `scoped_refptr`). `weak_ptr` capture in the SSRC callback prevents use-after-free during teardown. WebRTC clears the transformer when the receiver is destroyed (PeerConnection close); any frames still in the FIFO at that point are released by the deque destructor (the underlying `TransformableFrameInterface` instances are owned `unique_ptr`s and clean up automatically).

## Testing

After removing `ActiveAudioSsrcs`, the tap is the only discovery path in every mode — test and real. The existing CLI test bench validates it without modification:

- All-Reference, no mute: each ReferenceImpl peer must discover the others via the tap, add recvonly transceivers, and report `level ≥ 0.05` (current invariant in `validateGroupState`).
- Mixed (CustomImpl + ReferenceImpl), no mute: same invariant from both sides.
- Mute scenarios: muted peers must still be discovered (their packets carry encoded silence; the tap fires on first packet) and their `level` must read 0 (existing muted-peer invariant from the previous fix).

If any of these regress, the tap is broken — which is exactly the coverage we want.

No new CLI flags or SFU exports needed; the previous draft's `--suppress-active-audio-ssrcs` is moot.

## Out of scope (this design)

- **E2E `e2eEncryptDecrypt` wiring** is a separate fix, but this design pre-installs the surface it needs: `GRAudioFrameTransformer::DecryptHook` is a constructor parameter (nullptr today). The e2e PR captures `descriptor.e2eEncryptDecrypt` and passes a closure that decrypts the frame's `GetData()` and writes back via `SetData()` before the transformer calls `OnTransformedFrame`. No further structural changes — the transformer is already attached to every audio receiver.
- SSRC>int31 join-payload masking (separate fix).
- Push-style discovery via a new `GroupInstanceInterface::addIncomingAudioSsrcs(...)` method. May be added later but is not needed to fix the immediate problem.
- Video SSRC discovery — handled by the existing app-facing `dataChannelMessageReceived` callback for `ActiveVideoSsrcs` (and via `setRequestedVideoChannels` from MTProto data on iOS). The same per-receiver transformer pattern would extend to incoming video for video e2e, but that's outside the audio scope here.

## Risks

- **Buffer-flush correctness.** The tap holds frames until `releaseSsrc` fires. If the call is missed (bug in `onRenegotiationComplete`, race with `stop()`), the timeout clears the buffer at 1 s and the participant goes silent. The CLI integration tests catch this end-to-end: with `ActiveAudioSsrcs` removed, the tap is the *only* discovery path, so the existing `receivedAudio ≥ 0.05` invariant validates the full chain.
- **Tap-passthrough correctness.** Because the tap transformer remains attached after stream promotion, *every* live frame for an SSRC also passes through `Transform()` → `kDrained` branch → `OnTransformedFrame`. If the `kDrained` branch is broken or skipped, every audio frame for every promoted SSRC is silently dropped. Same CLI test coverage applies: the moment passthrough breaks, no peer hears anyone.
- **NetEQ jitter-buffer burst on flush.** `releaseSsrc` flushes up to ~1 s of audio (`kMaxBufferedFramesPerSsrc` × 20 ms = 1.2 s) into the receive stream in one tight loop. NetEQ sees this as a jitter-buffer fill spike. It will normally play out at the natural 50 fps rate, but the burst may exceed `audio_jitter_buffer_max_packets_` and trigger acceleration, deletion, or PLC artifacts. Worst case: a brief audio glitch when a new participant first speaks. Acceptable; mitigated by setting `kMaxBufferedFramesPerSsrc` aggressively low (e.g., 30 frames = 600 ms) if the artifact proves audible.
- **Race window during release.** Marking `kDrained` while still holding the lock prevents concurrent `Transform()` from buffering a doomed frame. There is still a microsecond between unlock and the start of the drain loop where a `Transform()` could beat `releaseSsrc` to the live-passthrough path — but the result is just the new frame arriving at the decoder *before* the buffered backlog. NetEQ reorders by RTP timestamp; harmless.
- **Renegotiation storm.** Mitigated by the 250 ms debounce in `scheduleDiscoveryRenegotiation()`: a burst of N SSRCs in the window collapses to one renegotiation. The existing `_isRenegotiating` / `_pendingRenegotiation` flags handle the case where another renegotiation source (e.g., `setRequestedVideoChannels`) is concurrently in flight. The first-sight check in the tap prevents duplicate per-SSRC scheduling.
- **Memory-pressure cap.** Worst-case buffered audio: `kMaxConcurrentBufferedSsrcs` × `kMaxBufferedFramesPerSsrc` × ~80 bytes/frame ≈ 64 × 60 × 80 = 308 KB. Both bounds are deliberately conservative — a misbehaving SFU sending unique SSRCs per packet hits the SSRC cap and drops further new ones rather than allocating unbounded memory.
- **Stream promotion is still load-bearing for buffered audio.** Live frames flow correctly because we explicitly install the transformer on each recvonly receiver — that path is no longer dependent on internal WebRTC behavior. *Buffered frames* still rely on the unsignaled→signaled stream promotion: the per-SSRC `TransformedFrameCallback` we got at first-sight is the one we replay through. If a future WebRTC update breaks promotion (constructs a new signaled stream and orphans the unsignaled one), `releaseSsrc` would dispatch frames into the orphan and they'd never decode. The CLI tests catch this — buffered audio would be silent during the first 250–500 ms of every new participant, which the audio-level invariant will flag in mute-style tests if extended to assert on first-second levels.

## Files touched (anticipated)

- `submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp` — add `GRAudioFrameTransformer` (per-SSRC FIFO + `releaseSsrc` + `decryptHook` callable initialized to nullptr); construct + install on mid=0's receiver in `start()`; install on each new recvonly receiver in `renegotiate()`; add `handleDiscoveredAudioSsrc` and `scheduleDiscoveryRenegotiation`; **delete `handleActiveAudioSsrcs` and its dispatch in `onDataChannelMessage`**; call `releaseSsrc` from `onRenegotiationComplete` for each newly-mid-assigned SSRC; add `_audioFrameTransformer` (`scoped_refptr<GRAudioFrameTransformer>`) and `_discoveryRenegotiationScheduled` members.
- `submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/sfu.go` — **delete `ActiveAudioSsrcs` broadcast** (message construction at `sfu.go:987` and any per-join trigger).
- `submodules/TgVoipWebrtc/CLAUDE.md` and `submodules/TgVoipWebrtc/tgcalls/tools/cli/CLAUDE.md` — update to reflect that ReferenceImpl discovers SSRCs via a `FrameTransformer` tap on mid=0; remove `ActiveAudioSsrcs`/`SetDefaultRawAudioSink` references.
- No iOS-side changes (`OngoingCallThreadLocalContext.mm` etc.) — the existing `requestMediaChannelDescriptions` callback already supports the discovery path.
- No CLI changes (`tools/cli/main.cpp`, `group_mode.cpp/.h`) — the existing tests validate the tap directly.
