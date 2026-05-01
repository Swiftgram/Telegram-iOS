# GroupInstanceReferenceImpl Reactive SSRC Discovery — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `GroupInstanceReferenceImpl`'s test-SFU-only `ActiveAudioSsrcs` discovery path with a per-receiver `webrtc::FrameTransformerInterface` that observes incoming SSRCs at the depacketizer-to-decoder boundary, buffers their first ≤1 s of frames, drives an audio recvonly transceiver to be added via the existing `_requestMediaChannelDescriptions` callback, and flushes the buffer once renegotiation completes — restoring audio in real Telegram group calls without a startup gap.

**Architecture:** A single `GRAudioFrameTransformer` instance is installed on every audio receiver in this `GroupInstanceReferenceInternal` (mid=0 sendrecv outgoing, plus each recvonly transceiver as it's added). It maintains a per-SSRC state machine (`kBuffering` → `kDrained`) and exposes `releaseSsrc(ssrc)` for the discovery flow to call after `onRenegotiationComplete`. A 250 ms debounce coalesces bursts into one renegotiation. The `ActiveAudioSsrcs` data-channel mechanism (test-SFU only) is removed from both the Go SFU and the C++ ReferenceImpl so the tap is the single discovery path in test and production.

**Tech Stack:** C++17, WebRTC `FrameTransformerInterface` API, Bazel 8.4.2, the existing tgcalls test bench (Go/Pion SFU + `tgcalls_cli` integration tests).

---

## Reference: Spec & key call-sites

- **Spec:** `docs/superpowers/specs/2026-05-01-groupref-ssrc-discovery-design.md`
- **WebRTC plumbing reference:** `third-party/webrtc/webrtc/api/frame_transformer_interface.h` (the `FrameTransformerInterface` / `TransformableFrameInterface` / `TransformedFrameCallback` contract); `third-party/webrtc/webrtc/media/engine/webrtc_voice_engine.cc:2240-2266` (the unsignaled→signaled stream promotion path that lets buffered frames flow into the same receive stream).
- **C++ files we modify:** `submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp` (only `.cpp`; the `.h` doesn't change).
- **Go file we modify:** `submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/sfu.go`.
- **Docs to refresh:** `submodules/TgVoipWebrtc/CLAUDE.md` (ReferenceImpl section), `submodules/TgVoipWebrtc/tgcalls/tools/cli/CLAUDE.md` (group-mode SSRC discovery flow), `submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/CLAUDE.md` (drop the `ActiveAudioSsrcs` mention).

## File structure

| File | Change | Responsibility |
|---|---|---|
| `submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp` | modify | Add `GRAudioFrameTransformer` (anonymous-namespace), wire into `start()` and `renegotiate()`, add `handleDiscoveredAudioSsrc` / `scheduleDiscoveryRenegotiation`, delete `handleActiveAudioSsrcs` and its dispatch, call `releaseSsrc` in `onRenegotiationComplete`, add `_audioFrameTransformer` and `_discoveryRenegotiationScheduled` members. |
| `submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/sfu.go` | modify | Delete `buildActiveSSRCsMessage`, `broadcastActiveSSRCs`, both call-sites (post-Join goroutine line 330, Leave line 1061). The `participantSSRCs` audio-collection helper used by `broadcastActiveSSRCs` is otherwise unused; remove it. |
| `submodules/TgVoipWebrtc/CLAUDE.md` | modify | Update the "GroupInstanceReferenceImpl" section: SSRC discovery now via tap; remove "ActiveAudioSsrcs" reference; add note that `_audioFrameTransformer` is the seam where e2e decrypt will land. |
| `submodules/TgVoipWebrtc/tgcalls/tools/cli/CLAUDE.md` | modify | Remove the `ActiveAudioSsrcs` line from the group-mode flow description. |
| `submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/CLAUDE.md` | modify | Remove "ActiveAudioSsrcs" from the `sfu.go` bullet. |

No new files. No iOS code touched. No CLI test-tool code touched (we ride on the existing `--mute-participants` and per-SSRC level invariants from the previous fix).

---

## Test bench reference

The existing CLI test (built earlier in this branch) is the integration harness. After every code change, the regression sweep is:

```bash
/Users/isaac/build/telegram/telegram-ios/build-input/bazel-8.4.2-darwin-arm64 \
  build //submodules/TgVoipWebrtc/tgcalls/tools/cli:tgcalls_cli 2>&1 | tail -3

# T1: All-Reference, no mute — must SUCCESS
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 0 --reference-participants 3 --duration 6 --quiet
# Expected: "Result: SUCCESS", exit code 0

# T2: Mixed (2C+2R) — must SUCCESS
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 2 --reference-participants 2 --duration 6 --quiet

# T3: All-Reference with P0 muted — must SUCCESS (muted-peer invariant)
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 0 --reference-participants 3 --mute-participants 0 --duration 6 --quiet

# T4: Mixed muted (custom side muted) — must SUCCESS
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 1 --reference-participants 2 --mute-participants 0 --duration 6 --quiet

# T5: Mixed muted (reference side muted) — must SUCCESS
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 2 --reference-participants 1 --mute-participants 2 --duration 6 --quiet
```

Tasks below name a specific subset of T1–T5 to run as the verification step. Always run **all five** before the final commit of each task — the muted-peer invariant from the audio-level fix is the strongest detector for routing regressions.

---

### Task 1: Delete `ActiveAudioSsrcs` from the test SFU

**Files:**
- Modify: `submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/sfu.go`

**Why first:** Forces every subsequent test run to exercise the discovery path we're about to build. Until the tap is in, all-Reference tests will fail (expected); mixed tests will still pass (CustomImpl discovers via raw RTP). This intentional regression is the visible TDD-red for the rest of the plan.

- [ ] **Step 1: Read the current state**

Confirm the three locations with:

```bash
grep -n "broadcastActiveSSRCs\|buildActiveSSRCsMessage" \
  /Users/isaac/build/telegram/telegram-ios/submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/sfu.go
```

Expected output:
```
330:		s.broadcastActiveSSRCs()
886:// broadcastActiveSSRCs sends the current set of active audio SSRCs to all connected participants.
888:func (s *SFU) broadcastActiveSSRCs() {
911:		msg := buildActiveSSRCsMessage(ssrcs)
986:func buildActiveSSRCsMessage(ssrcs []int32) string {
1061:	s.broadcastActiveSSRCs()
```

- [ ] **Step 2: Delete the two call-sites**

Remove the line `s.broadcastActiveSSRCs()` at line 330 (inside the post-Join goroutine, immediately above `s.broadcastActiveVideoSSRCs()`). Remove the line `s.broadcastActiveSSRCs()` at line 1061 (inside `Leave`, immediately above `s.broadcastActiveVideoSSRCs()`).

- [ ] **Step 3: Delete `broadcastActiveSSRCs` and `buildActiveSSRCsMessage`**

Delete the entire function `broadcastActiveSSRCs` (the doc-comment at line 886 through the closing `}` of the function around line 916, including the `participantSSRCs` map it builds locally).

Delete the entire function `buildActiveSSRCsMessage` (line 986 through line 996).

- [ ] **Step 4: Verify nothing else references them**

```bash
grep -n "broadcastActiveSSRCs\|buildActiveSSRCsMessage\|ActiveAudioSsrcs" \
  /Users/isaac/build/telegram/telegram-ios/submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/sfu.go
```

Expected output: empty.

- [ ] **Step 5: Build**

```bash
/Users/isaac/build/telegram/telegram-ios/build-input/bazel-8.4.2-darwin-arm64 \
  build //submodules/TgVoipWebrtc/tgcalls/tools/cli:tgcalls_cli 2>&1 | tail -3
```

Expected: `INFO: Build completed successfully`.

- [ ] **Step 6: Run T1 (all-Reference) — confirm RED**

```bash
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 0 --reference-participants 3 --duration 6 --quiet
echo "EXIT=$?"
```

Expected: `Result: FAILED`, `Audio received: 0/3`, `EXIT=1`. (No discovery → no recvonly transceivers → no audio.)

- [ ] **Step 7: Run T2 (mixed) — confirm partial regression**

```bash
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 2 --reference-participants 2 --duration 6 --quiet
echo "EXIT=$?"
```

Expected: `Result: FAILED`. CustomImpl peers will still discover ReferenceImpl audio via raw RTP (so they receive ReferenceImpl audio), but ReferenceImpl peers cannot discover anyone (so they receive nothing). `Audio received` will report something less than 4/4.

- [ ] **Step 8: Commit the intentional regression**

```bash
cd /Users/isaac/build/telegram/telegram-ios
git add submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/sfu.go
git commit -m "$(cat <<'EOF'
test sfu: remove ActiveAudioSsrcs broadcast

The test-only ActiveAudioSsrcs colibri message is being replaced by
ReferenceImpl's per-receiver FrameTransformer-based discovery (next
commits). Removing the message first forces every subsequent test
run to exercise the new code path — keeping the message in place
would let test passes mask production-real bugs.

T1/T2 currently FAIL as expected; T3-T5 likewise — the muted-peer
invariant cannot hold without working discovery. All restored by the
end of this PR.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Delete `handleActiveAudioSsrcs` from `GroupInstanceReferenceImpl`

**Files:**
- Modify: `submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp`

**Why now:** The handler is now dead code (no SFU sends `ActiveAudioSsrcs` anymore). Removing it before adding the new path means we don't temporarily have two SSRC-add paths that could both insert the same entry into `_remoteSsrcs`.

- [ ] **Step 1: Confirm the call sites**

```bash
grep -n "handleActiveAudioSsrcs\|colibriClass.*ActiveAudio" \
  /Users/isaac/build/telegram/telegram-ios/submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp
```

Expected:
```
1060:        if (colibriClass == "ActiveAudioSsrcs") {
1061:            handleActiveAudioSsrcs(json);
1063:    void handleActiveAudioSsrcs(json11::Json const &json) {
```

- [ ] **Step 2: Read the dispatch site**

Read lines 1048–1067 of `GroupInstanceReferenceImpl.cpp` to confirm the surrounding context of `onDataChannelMessage`.

- [ ] **Step 3: Remove the dispatch (lines 1056–1067)**

Inside `onDataChannelMessage`, locate the `colibriClass == "ActiveAudioSsrcs"` branch and the comment immediately above (`// ActiveVideoSsrcs and SenderVideoConstraints are handled by the` ... `// setRequestedVideoChannels() in response.`). Delete the JSON parse block, the colibriClass extraction, and the if-branch that calls `handleActiveAudioSsrcs(json)`.

The remaining body of `onDataChannelMessage` should consist of the `_dataChannelMessageReceived` forwarding only:

```cpp
    void onDataChannelMessage(std::string const &msg) {
        // Forward all data channel messages to the application.
        // Audio SSRCs are now discovered by the per-receiver frame
        // transformer (see GRAudioFrameTransformer); video channel
        // requests are app-driven via setRequestedVideoChannels.
        if (_dataChannelMessageReceived) {
            _dataChannelMessageReceived(msg);
        }
    }
```

- [ ] **Step 4: Delete `handleActiveAudioSsrcs`**

Delete the entire function `handleActiveAudioSsrcs(json11::Json const &json)` (starts at the line that previously matched `1063:    void handleActiveAudioSsrcs(json11::Json const &json) {`, ends at the matching `}`). It's roughly 60 lines including the diff loop and the `_requestMediaChannelDescriptions` call.

- [ ] **Step 5: Verify nothing else references it**

```bash
grep -n "handleActiveAudioSsrcs\|ActiveAudioSsrcs" \
  /Users/isaac/build/telegram/telegram-ios/submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp
```

Expected: empty.

- [ ] **Step 6: Build**

```bash
/Users/isaac/build/telegram/telegram-ios/build-input/bazel-8.4.2-darwin-arm64 \
  build //submodules/TgVoipWebrtc/tgcalls/tools/cli:tgcalls_cli 2>&1 | tail -3
```

Expected: `INFO: Build completed successfully`.

- [ ] **Step 7: Run T1 — still RED, same reason**

```bash
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 0 --reference-participants 3 --duration 6 --quiet
echo "EXIT=$?"
```

Expected: `Result: FAILED`, `EXIT=1`. (No regression added beyond Task 1; we just deleted dead code.)

- [ ] **Step 8: Commit**

```bash
cd /Users/isaac/build/telegram/telegram-ios
git add submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp
git commit -m "$(cat <<'EOF'
GroupInstanceReferenceImpl: remove handleActiveAudioSsrcs

ActiveAudioSsrcs was a test-SFU-only colibri message. With the test
SFU no longer sending it, the handler is dead code. Removing now
before introducing the new discovery path so we don't briefly have
two paths inserting into _remoteSsrcs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Add `GRAudioFrameTransformer` skeleton (no behavior yet)

**Files:**
- Modify: `submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp`

**Why staged:** Adding the class first as a do-nothing pass-through transformer lets us verify the WebRTC plumbing works (the catch-all transformer never breaks audio, OnTransformedFrame is reachable) before we layer on the per-SSRC state machine. Initially we also install nothing — the class just compiles.

- [ ] **Step 1: Locate the anonymous namespace insertion point**

Read lines 109–148 of `GroupInstanceReferenceImpl.cpp` to confirm where the anonymous namespace ends (the `} // anonymous namespace` line).

- [ ] **Step 2: Add the class right before `} // anonymous namespace`**

Insert the following code immediately before the closing `} // anonymous namespace` (after `GRCreateSDPObserver`):

```cpp
// --- Per-receiver audio frame transformer ---
//
// One instance is installed (via `RtpReceiverInterface::SetDepacketizerToDecoderFrameTransformer`)
// on every audio receiver in this GroupInstanceReferenceInternal:
//   - mid=0 sendrecv outgoing audio (its receive side acts as the catch-all
//     for unsignaled SSRCs);
//   - each recvonly audio transceiver added by the SSRC-discovery flow.
//
// Behavior per SSRC:
//   - First-sight (no entry yet): notify discovery; buffer the frame.
//   - kBuffering (waiting for renegotiation): append to per-SSRC FIFO.
//   - kDrained (releaseSsrc has fired): pass through immediately.
//
// `releaseSsrc(ssrc)` is invoked by ReferenceImpl on the media thread
// from `onRenegotiationComplete` once a recvonly transceiver owns the
// SSRC. The transformer drains the per-SSRC FIFO via OnTransformedFrame
// and transitions the entry to kDrained.
//
// `decryptHook` is reserved for the e2e fix (separate PR). Today it is
// nullptr and the transformer just forwards frames unchanged.
class GRAudioFrameTransformer : public webrtc::FrameTransformerInterface {
public:
    using SsrcCallback = std::function<void(uint32_t ssrc)>;
    using DecryptHook = std::function<bool(webrtc::TransformableFrameInterface&)>;

    GRAudioFrameTransformer(SsrcCallback onNewSsrc,
                            DecryptHook decrypt,
                            rtc::Thread* mediaThread)
        : _onNewSsrc(std::move(onNewSsrc)),
          _decrypt(std::move(decrypt)),
          _mediaThread(mediaThread) {}

    // Stub — to be filled in Task 4.
    void Transform(std::unique_ptr<webrtc::TransformableFrameInterface> frame) override {
        // Pass-through for now (verifies plumbing).
        webrtc::MutexLock lock(&_mu);
        const uint32_t ssrc = frame->GetSsrc();
        rtc::scoped_refptr<webrtc::TransformedFrameCallback> sink;
        auto it = _perSsrcSinks.find(ssrc);
        if (it != _perSsrcSinks.end()) {
            sink = it->second;
        } else if (_broadcastSink) {
            sink = _broadcastSink;
        }
        if (!sink) return;
        sink->OnTransformedFrame(std::move(frame));
    }

    // Stub — to be filled in Task 4.
    void releaseSsrc(uint32_t /*ssrc*/) {}

    void RegisterTransformedFrameCallback(
            rtc::scoped_refptr<webrtc::TransformedFrameCallback> cb) override {
        webrtc::MutexLock lock(&_mu);
        _broadcastSink = std::move(cb);
    }
    void RegisterTransformedFrameSinkCallback(
            rtc::scoped_refptr<webrtc::TransformedFrameCallback> cb,
            uint32_t ssrc) override {
        webrtc::MutexLock lock(&_mu);
        _perSsrcSinks[ssrc] = std::move(cb);
    }
    void UnregisterTransformedFrameCallback() override {
        webrtc::MutexLock lock(&_mu);
        _broadcastSink = nullptr;
    }
    void UnregisterTransformedFrameSinkCallback(uint32_t ssrc) override {
        webrtc::MutexLock lock(&_mu);
        _perSsrcSinks.erase(ssrc);
    }

private:
    SsrcCallback _onNewSsrc;
    DecryptHook _decrypt;
    rtc::Thread* _mediaThread; // identity only; not used for thread-affine asserts in this skeleton

    webrtc::Mutex _mu;
    rtc::scoped_refptr<webrtc::TransformedFrameCallback> _broadcastSink RTC_GUARDED_BY(_mu);
    std::map<uint32_t, rtc::scoped_refptr<webrtc::TransformedFrameCallback>> _perSsrcSinks RTC_GUARDED_BY(_mu);
};
```

- [ ] **Step 3: Add a `webrtc::Mutex` include if missing**

```bash
grep -n "rtc_base/synchronization/mutex.h\|webrtc::Mutex\b" \
  /Users/isaac/build/telegram/telegram-ios/submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp | head -5
```

If the include is missing, add to the includes near the top of the file (after the existing webrtc includes):

```cpp
#include "rtc_base/synchronization/mutex.h"
```

- [ ] **Step 4: Build**

```bash
/Users/isaac/build/telegram/telegram-ios/build-input/bazel-8.4.2-darwin-arm64 \
  build //submodules/TgVoipWebrtc/tgcalls/tools/cli:tgcalls_cli 2>&1 | tail -10
```

Expected: `INFO: Build completed successfully`.

If the build fails on `webrtc::Mutex` — try `#include "api/sequence_checker.h"` and use `webrtc::Mutex` from there, or fall back to `std::mutex` (the rest of the file already uses `<mutex>` via `_audioLevelsMutex` in `tools/cli/group_participant.cpp`; check what's available in `tgcalls/tgcalls/group/`).

- [ ] **Step 5: Run T1 — still expected to fail (we haven't installed the transformer yet)**

```bash
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 0 --reference-participants 3 --duration 6 --quiet
echo "EXIT=$?"
```

Expected: `Result: FAILED`, `EXIT=1`. The class is defined but unused — same red as Tasks 1–2.

- [ ] **Step 6: Commit**

```bash
cd /Users/isaac/build/telegram/telegram-ios
git add submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp
git commit -m "$(cat <<'EOF'
GroupInstanceReferenceImpl: add GRAudioFrameTransformer skeleton

Pass-through frame transformer scaffolding. Behavior (per-SSRC
buffering, releaseSsrc, decrypt hook) lands in the next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Implement the per-SSRC state machine in `GRAudioFrameTransformer`

**Files:**
- Modify: `submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp` (the class added in Task 3)

**Why staged:** Once installed (Task 5), this class becomes part of every audio frame's path. Splitting "skeleton" from "behavior" makes the diff small enough to review carefully — bugs here silently drop audio.

- [ ] **Step 1: Add the `Entry` struct, constants, and `_entries` map to the class**

Inside `class GRAudioFrameTransformer` (after `_perSsrcSinks` declaration), add:

```cpp
private:
    enum class SsrcState { kBuffering, kDrained };

    struct Entry {
        SsrcState state = SsrcState::kBuffering;
        std::deque<std::unique_ptr<webrtc::TransformableFrameInterface>> buffer;
        int64_t firstFrameTimeMs = 0;
    };

    static constexpr int64_t kSsrcDiscoveryTimeoutMs = 1000;
    static constexpr size_t kMaxBufferedFramesPerSsrc = 60;
    static constexpr size_t kMaxConcurrentBufferedSsrcs = 64;

    void evictExpired_n() RTC_EXCLUSIVE_LOCKS_REQUIRED(_mu);

    std::map<uint32_t, Entry> _entries RTC_GUARDED_BY(_mu);
```

Add `<deque>` to the includes if not already present (usually pulled in transitively):

```bash
grep -n "<deque>" /Users/isaac/build/telegram/telegram-ios/submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp
```

If missing, add `#include <deque>` near the top with the other STL includes.

- [ ] **Step 2: Replace `Transform` with the real implementation**

Replace the stub `Transform` body with:

```cpp
    void Transform(std::unique_ptr<webrtc::TransformableFrameInterface> frame) override {
        if (!frame) return;
        const uint32_t ssrc = frame->GetSsrc();

        // Path A: kDrained — pass through.
        // Path B: kBuffering — buffer.
        // Path C: new SSRC — insert + post discovery + buffer.
        // Path D: at the SSRC cap — drop silently.
        rtc::scoped_refptr<webrtc::TransformedFrameCallback> liveSink;
        bool notifyDiscovery = false;
        std::unique_ptr<webrtc::TransformableFrameInterface> liveFrame;
        {
            webrtc::MutexLock lock(&_mu);
            evictExpired_n();

            auto it = _entries.find(ssrc);
            if (it == _entries.end()) {
                if (_entries.size() >= kMaxConcurrentBufferedSsrcs) {
                    // Path D: drop without notify, no allocation.
                    return;
                }
                Entry entry;
                entry.firstFrameTimeMs = rtc::TimeMillis();
                entry.buffer.push_back(std::move(frame));
                _entries.emplace(ssrc, std::move(entry));
                notifyDiscovery = true;
            } else if (it->second.state == SsrcState::kBuffering) {
                if (it->second.buffer.size() >= kMaxBufferedFramesPerSsrc) {
                    it->second.buffer.pop_front();
                }
                it->second.buffer.push_back(std::move(frame));
            } else {
                // kDrained: pick the live sink and emit outside the lock.
                auto sinkIt = _perSsrcSinks.find(ssrc);
                if (sinkIt != _perSsrcSinks.end()) {
                    liveSink = sinkIt->second;
                } else {
                    liveSink = _broadcastSink;
                }
                liveFrame = std::move(frame);
            }
        }

        if (liveSink && liveFrame) {
            liveSink->OnTransformedFrame(std::move(liveFrame));
        }
        if (notifyDiscovery && _onNewSsrc) {
            _onNewSsrc(ssrc);
        }
    }
```

- [ ] **Step 3: Replace `releaseSsrc` with the real implementation**

Replace the stub `releaseSsrc` body with:

```cpp
    void releaseSsrc(uint32_t ssrc) {
        std::deque<std::unique_ptr<webrtc::TransformableFrameInterface>> toFlush;
        rtc::scoped_refptr<webrtc::TransformedFrameCallback> sink;
        {
            webrtc::MutexLock lock(&_mu);
            auto it = _entries.find(ssrc);
            if (it == _entries.end() || it->second.state == SsrcState::kDrained) {
                // Either the SSRC was unknown, or already drained. Mark drained
                // so future frames take the live-passthrough path.
                if (it == _entries.end()) {
                    Entry entry;
                    entry.state = SsrcState::kDrained;
                    entry.firstFrameTimeMs = rtc::TimeMillis();
                    _entries.emplace(ssrc, std::move(entry));
                }
                return;
            }
            it->second.state = SsrcState::kDrained;
            toFlush = std::move(it->second.buffer);

            auto sinkIt = _perSsrcSinks.find(ssrc);
            if (sinkIt != _perSsrcSinks.end()) {
                sink = sinkIt->second;
            } else {
                sink = _broadcastSink;
            }
        }

        if (!sink) return;
        while (!toFlush.empty()) {
            auto f = std::move(toFlush.front());
            toFlush.pop_front();
            sink->OnTransformedFrame(std::move(f));
        }
    }
```

- [ ] **Step 4: Implement `evictExpired_n`**

Add this private method definition inside the class (e.g., after `releaseSsrc`):

```cpp
    void evictExpired_n() RTC_EXCLUSIVE_LOCKS_REQUIRED(_mu) {
        const int64_t now = rtc::TimeMillis();
        for (auto& [ssrc, entry] : _entries) {
            if (entry.state == SsrcState::kBuffering &&
                !entry.buffer.empty() &&
                (now - entry.firstFrameTimeMs) > kSsrcDiscoveryTimeoutMs) {
                entry.buffer.clear();
                // Leave the entry in kBuffering with empty buffer so we don't
                // re-notify discovery. If the application ever recovers
                // (renegotiation completes belatedly), releaseSsrc will still
                // mark kDrained and live frames will flow through.
            }
        }
    }
```

- [ ] **Step 5: Add `rtc::TimeMillis` include if missing**

```bash
grep -n "rtc::TimeMillis\b\|rtc_base/time_utils.h" \
  /Users/isaac/build/telegram/telegram-ios/submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp | head -5
```

If only the call shows up but not the header, add:

```cpp
#include "rtc_base/time_utils.h"
```

near the other rtc_base includes.

- [ ] **Step 6: Build**

```bash
/Users/isaac/build/telegram/telegram-ios/build-input/bazel-8.4.2-darwin-arm64 \
  build //submodules/TgVoipWebrtc/tgcalls/tools/cli:tgcalls_cli 2>&1 | tail -10
```

Expected: `INFO: Build completed successfully`.

- [ ] **Step 7: Run T1 — still expected to fail (transformer still not installed)**

```bash
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 0 --reference-participants 3 --duration 6 --quiet
echo "EXIT=$?"
```

Expected: `Result: FAILED`, `EXIT=1`. Code is built but unused.

- [ ] **Step 8: Commit**

```bash
cd /Users/isaac/build/telegram/telegram-ios
git add submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp
git commit -m "$(cat <<'EOF'
GroupInstanceReferenceImpl: implement GRAudioFrameTransformer state machine

Per-SSRC buffer / drain / passthrough. releaseSsrc transitions
kBuffering→kDrained atomically (mark under lock, drain outside lock)
to avoid races. evictExpired_n bounds buffer lifetime to 1s.

Caps: kMaxConcurrentBufferedSsrcs=64, kMaxBufferedFramesPerSsrc=60.
Worst-case memory ≈ 308 KB.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Wire the transformer into `start()` (catch-all only) and observe discovery callback fires

**Files:**
- Modify: `submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp`

**Why staged:** Install on the catch-all and prove `Transform` fires (via the `_onNewSsrc` callback). Discovery doesn't yet drive a renegotiation — that's the next task. After this task, T1 should still FAIL but with the discovery callback observably firing.

- [ ] **Step 1: Add the member field**

Locate the `Audio.` block in the private member section (around line 1556 — `_outgoingAudioTrack`, `_outgoingAudioTransceiver`). Add immediately after:

```cpp
    // Per-receiver audio frame transformer (catch-all + every recvonly).
    rtc::scoped_refptr<GRAudioFrameTransformer> _audioFrameTransformer;
```

- [ ] **Step 2: Add a forward declaration for `handleDiscoveredAudioSsrc` (function defined in Task 6)**

Inside the class, near the other private method declarations / definitions for `handleActiveAudioSsrcs`-replacement work — for now, declare a stub:

```cpp
    void handleDiscoveredAudioSsrc(uint32_t ssrc) {
        // To be implemented in Task 6.
        RTC_LOG(LS_INFO) << "GroupRef: discovered audio SSRC " << ssrc;
    }
```

Place this near the existing media-thread methods (e.g., near `wireRemoteAudioLevelSinks`).

- [ ] **Step 3: Construct + install the transformer in `start()`**

Locate the block after `_outgoingAudioTransceiver` is created (around line 386, immediately after the `params.encodings[0].max_bitrate_bps = ...; _outgoingAudioTransceiver->sender()->SetParameters(params);` block). Insert before `_outgoingAudioTrack->set_enabled(false); // Muted by default.`:

```cpp
            // Install the audio frame transformer on mid=0's receiver. The
            // receive side of this sendrecv transceiver is PeerConnection's
            // catch-all for unsignaled SSRCs, so the transformer captures
            // every previously-unseen remote SSRC. The same instance is
            // attached to each recvonly receiver in renegotiate() so that
            // live audio passes through the transformer consistently
            // (and so the e2e PR has a single attachment point).
            _audioFrameTransformer = rtc::make_ref_counted<GRAudioFrameTransformer>(
                /*onNewSsrc=*/[weak, threads = _threads](uint32_t ssrc) {
                    threads->getMediaThread()->PostTask([weak, ssrc]() {
                        if (auto strong = weak.lock()) {
                            strong->handleDiscoveredAudioSsrc(ssrc);
                        }
                    });
                },
                /*decrypt=*/nullptr,                 // wired by the e2e PR
                /*mediaThread=*/_threads->getMediaThread().get());
            _outgoingAudioTransceiver->receiver()
                ->SetDepacketizerToDecoderFrameTransformer(_audioFrameTransformer);
```

Note: `weak` is the `weak_ptr<GroupInstanceReferenceInternal>` already in scope earlier in `start()`. Verify by re-reading the start of `start()`:

```bash
sed -n '173,195p' /Users/isaac/build/telegram/telegram-ios/submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp
```

If `weak` is not in scope at the insertion point, declare locally:

```cpp
            const auto weak = std::weak_ptr<GroupInstanceReferenceInternal>(shared_from_this());
```

- [ ] **Step 4: Build**

```bash
/Users/isaac/build/telegram/telegram-ios/build-input/bazel-8.4.2-darwin-arm64 \
  build //submodules/TgVoipWebrtc/tgcalls/tools/cli:tgcalls_cli 2>&1 | tail -10
```

Expected: `INFO: Build completed successfully`.

- [ ] **Step 5: Run T1 with verbose output — confirm discovery callback fires**

```bash
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 0 --reference-participants 3 --duration 6 2>&1 \
  | grep "discovered audio SSRC" | head -10
```

Expected: at least one `GroupRef: discovered audio SSRC <ssrc>` line per remote peer per participant. (Logs go through `LogSinkImpl` which writes to a per-participant log file then deletes; if the grep returns nothing, briefly add `fprintf(stderr, "...")` mirroring the RTC_LOG to verify, then revert before commit.)

- [ ] **Step 6: Run T1 (full) — still expected to FAIL**

```bash
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 0 --reference-participants 3 --duration 6 --quiet
echo "EXIT=$?"
```

Expected: `Result: FAILED`. The handler is a logging stub; no recvonly transceiver is added; audio is dropped (no `OnTransformedFrame` call yet because the entry is `kBuffering` indefinitely).

- [ ] **Step 7: Commit**

```bash
cd /Users/isaac/build/telegram/telegram-ios
git add submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp
git commit -m "$(cat <<'EOF'
GroupInstanceReferenceImpl: install GRAudioFrameTransformer on mid=0

The transformer is now in the depacketizer path of mid=0's receiver
(PeerConnection's catch-all for unsignaled audio). Every previously-
unseen SSRC fires the discovery callback, which currently just logs.
The next commit drives renegotiation and flushes buffered audio.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Implement `handleDiscoveredAudioSsrc` + `scheduleDiscoveryRenegotiation` and call `releaseSsrc` from `onRenegotiationComplete`

**Files:**
- Modify: `submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp`

**Why staged:** This is the GREEN step — the test harness should pass for the first time after this task. Wiring discovery → renegotiation → release closes the loop, but until we also install the transformer on each recvonly receiver (Task 7), live frames after the flush continue to take the catch-all path. That's tolerable today (catch-all is the same instance) but Task 7 makes it explicit and future-proof.

- [ ] **Step 1: Add `_discoveryRenegotiationScheduled` member**

In the private member section, near `_isRenegotiating`:

```cpp
    // Discovery-renegotiation debounce.
    bool _discoveryRenegotiationScheduled = false;
```

- [ ] **Step 2: Replace the `handleDiscoveredAudioSsrc` stub with the real implementation**

```cpp
    // Single entry point for adding a remote audio SSRC. Runs on the
    // media thread (posted to from the worker-thread frame transformer
    // callback).
    void handleDiscoveredAudioSsrc(uint32_t ssrc) {
        if (ssrc == 0) return;
        if (ssrc == _outgoingSsrc) return;
        if (_remoteSsrcs.count(ssrc) > 0) return;

        std::string mid = std::to_string(_nextMid++);
        RemoteSsrcInfo info;
        info.mid = mid;
        _remoteSsrcs.emplace(ssrc, std::move(info));

        if (_requestMediaChannelDescriptions) {
            _requestMediaChannelDescriptions({ssrc},
                [](std::vector<MediaChannelDescription>&&) {});
        }
        scheduleDiscoveryRenegotiation();

        RTC_LOG(LS_INFO) << "GroupRef: queued discovered audio SSRC " << ssrc
                         << " (mid=" << mid << ")";
    }
```

- [ ] **Step 3: Add `scheduleDiscoveryRenegotiation`**

Place near the existing `renegotiate()` method:

```cpp
    static constexpr int kDiscoveryRenegotiationDelayMs = 250;

    void scheduleDiscoveryRenegotiation() {
        if (_discoveryRenegotiationScheduled) return;
        _discoveryRenegotiationScheduled = true;

        const auto weak = std::weak_ptr<GroupInstanceReferenceInternal>(shared_from_this());
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

- [ ] **Step 4: Add the `releaseSsrc` loop in `onRenegotiationComplete`**

Locate `onRenegotiationComplete()` (around line 1314). Insert after `wireRemoteAudioLevelSinks();` and before `_isRenegotiating = false;`:

```cpp
        if (_audioFrameTransformer) {
            for (auto& [ssrc, info] : _remoteSsrcs) {
                if (info.transceiver && info.transceiver->mid().has_value()) {
                    _audioFrameTransformer->releaseSsrc(ssrc);
                }
            }
        }
```

- [ ] **Step 5: Build**

```bash
/Users/isaac/build/telegram/telegram-ios/build-input/bazel-8.4.2-darwin-arm64 \
  build //submodules/TgVoipWebrtc/tgcalls/tools/cli:tgcalls_cli 2>&1 | tail -10
```

Expected: `INFO: Build completed successfully`.

- [ ] **Step 6: Run T1 — should now SUCCESS**

```bash
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 0 --reference-participants 3 --duration 6 --quiet
echo "EXIT=$?"
```

Expected: `Result: SUCCESS`, `Audio received: 3/3`, `EXIT=0`.

If FAIL: re-read the spec's "Where flushed frames actually go" section. The most likely issue is that the per-SSRC sink callback registered when the unsignaled stream was created is no longer the one routing to the (now-promoted) audio receive stream's decoder. Add a one-shot debug print inside `releaseSsrc` to confirm `sink != nullptr` and `toFlush.size() > 0`.

- [ ] **Step 7: Run T2-T5 — verify no regressions**

Run each scenario from the "Test bench reference" block above (T1 through T5). All five must report `Result: SUCCESS` and `EXIT=0`.

If T3-T5 (muted-peer scenarios) pass: the muted-peer invariant from the previous fix still holds, so the per-receiver audio-level sinks are correctly wired and reading PCM from the post-promotion stream.

- [ ] **Step 8: Commit**

```bash
cd /Users/isaac/build/telegram/telegram-ios
git add submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp
git commit -m "$(cat <<'EOF'
GroupInstanceReferenceImpl: drive discovery renegotiation, flush buffer

- handleDiscoveredAudioSsrc inserts into _remoteSsrcs, fires
  _requestMediaChannelDescriptions per SSRC, schedules a debounced
  renegotiation.
- scheduleDiscoveryRenegotiation coalesces bursts: at most one
  renegotiation per 250ms, regardless of how many SSRCs land in
  the window.
- onRenegotiationComplete iterates _remoteSsrcs and calls
  releaseSsrc(ssrc) for every entry whose transceiver now has a
  mid, draining the per-SSRC FIFO into OnTransformedFrame so the
  buffered audio plays without a startup gap.

T1-T5 all pass.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Install `_audioFrameTransformer` on every recvonly transceiver as it's added

**Files:**
- Modify: `submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp`

**Why now (not in Task 6):** Today the catch-all transformer covers live audio for promoted streams (it's already on the stream from the unsignaled-stream creation path). Explicitly installing it on each recvonly receiver removes our reliance on internal WebRTC stream-promotion behavior carrying the transformer along, and matches the exact attachment pattern the e2e PR will use.

- [ ] **Step 1: Find the AddTransceiver call in `renegotiate()`**

```bash
grep -n "AddTransceiver(cricket::MEDIA_TYPE_AUDIO" \
  /Users/isaac/build/telegram/telegram-ios/submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp
```

Expected: a single hit inside `renegotiate()` (around line 1142).

- [ ] **Step 2: Attach the transformer right after the transceiver is created**

Modify the block that handles the success branch of `AddTransceiver`. Original:

```cpp
                auto result = _peerConnection->AddTransceiver(cricket::MEDIA_TYPE_AUDIO, init);
                if (result.ok()) {
                    info.transceiver = result.value();
                    RTC_LOG(LS_INFO) << "GroupRef: Added recvonly transceiver for SSRC " << ssrc;
                }
```

Replace with:

```cpp
                auto result = _peerConnection->AddTransceiver(cricket::MEDIA_TYPE_AUDIO, init);
                if (result.ok()) {
                    info.transceiver = result.value();
                    if (_audioFrameTransformer) {
                        info.transceiver->receiver()
                            ->SetDepacketizerToDecoderFrameTransformer(_audioFrameTransformer);
                    }
                    RTC_LOG(LS_INFO) << "GroupRef: Added recvonly transceiver for SSRC " << ssrc;
                }
```

- [ ] **Step 3: Build**

```bash
/Users/isaac/build/telegram/telegram-ios/build-input/bazel-8.4.2-darwin-arm64 \
  build //submodules/TgVoipWebrtc/tgcalls/tools/cli:tgcalls_cli 2>&1 | tail -3
```

Expected: `INFO: Build completed successfully`.

- [ ] **Step 4: Run T1-T5 — must all SUCCESS**

```bash
for cfg in \
  "0 3 --duration 6" \
  "2 2 --duration 6" \
  "0 3 --mute-participants 0 --duration 6" \
  "1 2 --mute-participants 0 --duration 6" \
  "2 1 --mute-participants 2 --duration 6"; do
    /Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
      --mode group --participants $cfg --quiet 2>&1 | tail -3
    echo "EXIT=$?"; echo "---"
done
```

Each block must end with `Result: SUCCESS` and `EXIT=0`.

- [ ] **Step 5: Commit**

```bash
cd /Users/isaac/build/telegram/telegram-ios
git add submodules/TgVoipWebrtc/tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp
git commit -m "$(cat <<'EOF'
GroupInstanceReferenceImpl: attach frame transformer to each recvonly receiver

Live audio for a promoted SSRC was already flowing through our
transformer (carried over from the unsignaled stream creation
path), but we depended on internal WebRTC stream-promotion
behavior to make that work. Explicit per-receiver attachment
removes that dependency and matches what the e2e PR will need.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Documentation refresh

**Files:**
- Modify: `submodules/TgVoipWebrtc/CLAUDE.md`
- Modify: `submodules/TgVoipWebrtc/tgcalls/tools/cli/CLAUDE.md`
- Modify: `submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/CLAUDE.md`

- [ ] **Step 1: Update `submodules/TgVoipWebrtc/CLAUDE.md` — ReferenceImpl section**

Find the "GroupInstanceReferenceImpl" section. Update the "Dynamic Participant Handling → Audio" sub-bullet:

Before (or similar):
> 1. SFU sends `{"colibriClass":"ActiveAudioSsrcs","ssrcs":[54321,98765]}` over data channel
> 2. Client diffs against known SSRCs
> 3. New SSRCs: add recvonly audio transceiver → renegotiate (new offer + constructed answer mirroring offer mids)
> 4. Removed SSRCs: clean up from tracking map

After:
> 1. `GRAudioFrameTransformer` (installed on mid=0's receiver and on every recvonly audio receiver) sees a frame with an unknown SSRC at the depacketizer→decoder boundary, buffers it, and notifies the media thread.
> 2. `handleDiscoveredAudioSsrc` inserts the SSRC into `_remoteSsrcs`, fires `_requestMediaChannelDescriptions({ssrc}, ...)` (matches CustomImpl's contract), and schedules a 250 ms-debounced renegotiation.
> 3. Renegotiation adds a recvonly transceiver bound to the new SSRC; `buildRemoteAnswer` includes the SSRC on the new m-line; `WebRtcVoiceReceiveChannel::AddRecvStream` promotes the existing unsignaled stream in place.
> 4. `onRenegotiationComplete` calls `_audioFrameTransformer->releaseSsrc(ssrc)`, which drains the buffered FIFO via `OnTransformedFrame` so the user hears the participant's first ~250–500 ms of audio without a gap.
> 5. Subsequent live frames for the SSRC pass through the transformer's `kDrained` branch directly to the decoder.
>
> The `colibriClass=ActiveAudioSsrcs` data-channel mechanism (test-SFU only) was removed; the tap is the single discovery path. Removed-SSRC handling is the same as CustomImpl's: stale recvonly transceivers stay in the SDP indefinitely; participant departures are tracked at the application layer (MTProto).

- [ ] **Step 2: Update `submodules/TgVoipWebrtc/tgcalls/tools/cli/CLAUDE.md` — group flow**

Find the "Architecture (Group)" section. Remove the bullet about `ActiveAudioSsrcs` ("SSRC discovery: SFU broadcasts `ActiveAudioSsrcs` and `ActiveVideoSsrcs` ...") and replace with:

> SSRC discovery: video SSRCs are broadcast via `ActiveVideoSsrcs` (used by the test app's `dataChannelMessageReceived` callback to call `setRequestedVideoChannels`). Audio SSRCs are discovered by `GroupInstanceReferenceImpl`'s per-receiver `GRAudioFrameTransformer` directly from incoming RTP — same shape CustomImpl uses (`receiveUnknownSsrcPacket` → `_requestMediaChannelDescriptions`).

- [ ] **Step 3: Update `submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/CLAUDE.md`**

In the bullet that lists `sfu.go`'s responsibilities, remove the phrase `'ActiveAudioSsrcs'/`ActiveVideoSsrcs' broadcasting` and replace with `ActiveVideoSsrcs broadcasting` (audio is no longer broadcast).

- [ ] **Step 4: Verify builds still work after the doc changes (defensive)**

```bash
/Users/isaac/build/telegram/telegram-ios/build-input/bazel-8.4.2-darwin-arm64 \
  build //submodules/TgVoipWebrtc/tgcalls/tools/cli:tgcalls_cli 2>&1 | tail -3
```

Expected: `INFO: Build completed successfully` (no source files touched, but a no-op build verifies the docs don't accidentally break a generated file).

- [ ] **Step 5: Commit**

```bash
cd /Users/isaac/build/telegram/telegram-ios
git add submodules/TgVoipWebrtc/CLAUDE.md \
        submodules/TgVoipWebrtc/tgcalls/tools/cli/CLAUDE.md \
        submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: ReferenceImpl SSRC discovery via per-receiver frame transformer

Document the new GRAudioFrameTransformer-based audio SSRC discovery
flow in both the tgcalls library overview and the test-bench notes.
Drop ActiveAudioSsrcs references — the message no longer exists.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Final regression sweep

**Files:** none changed.

- [ ] **Step 1: Run the full sweep**

```bash
echo "=== T1: All-Reference no mute ==="
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 0 --reference-participants 3 --duration 6 --quiet | tail -3
echo "EXIT=$?"

echo "=== T2: Mixed (2C+2R) no mute ==="
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 2 --reference-participants 2 --duration 6 --quiet | tail -3
echo "EXIT=$?"

echo "=== T3: All-Reference, P0 muted ==="
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 0 --reference-participants 3 --mute-participants 0 --duration 6 --quiet | tail -3
echo "EXIT=$?"

echo "=== T4: Mixed (1C+2R), custom muted ==="
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 1 --reference-participants 2 --mute-participants 0 --duration 6 --quiet | tail -3
echo "EXIT=$?"

echo "=== T5: Mixed (2C+1R), reference muted ==="
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 2 --reference-participants 1 --mute-participants 2 --duration 6 --quiet | tail -3
echo "EXIT=$?"
```

Expected: every block ends with `Result: SUCCESS` and `EXIT=0`.

- [ ] **Step 2: Confirm muted-peer level invariant explicitly (T3 verbose)**

```bash
/Users/isaac/build/telegram/telegram-ios/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli \
  --mode group --participants 0 --reference-participants 3 --mute-participants 0 --duration 6 2>&1 \
  | grep -E "Validate" | head -5
```

Expected:
```
Validate: OK:   P1 (ref) reported muted P0 (ssrc=...) at max level 0.000
Validate: OK:   P2 (ref) reported muted P0 (ssrc=...) at max level 0.000
```

- [ ] **Step 3: Confirm no leftover `ActiveAudioSsrcs` references**

```bash
grep -rn "ActiveAudioSsrcs\|handleActiveAudioSsrcs\|broadcastActiveSSRCs\|buildActiveSSRCsMessage" \
  /Users/isaac/build/telegram/telegram-ios/submodules/TgVoipWebrtc/ 2>/dev/null | grep -v ".log\|.o\|index/\|bazel-"
```

Expected: empty (or only matches inside `.git/`).

- [ ] **Step 4: Confirm git log structure**

```bash
cd /Users/isaac/build/telegram/telegram-ios
git log --oneline -10
```

Expected to see 8 new commits from this PR (Tasks 1, 2, 3, 4, 5, 6, 7, 8) since the previous baseline.

- [ ] **Step 5: This task has no commit**

The sweep is verification-only.

---

## Out of scope (do NOT touch in this PR)

- `descriptor.e2eEncryptDecrypt` wiring. The seam (`DecryptHook` constructor parameter on `GRAudioFrameTransformer`) is in place; the actual decrypt callback is the next PR.
- Outgoing-audio SSRC>int31 masking. Separate fix.
- Push-style discovery via a new `GroupInstanceInterface::addIncomingAudioSsrcs(...)` method.
- Removed-SSRC cleanup (recvonly transceivers stay in the SDP indefinitely — same as CustomImpl).
- iOS-side code changes — the existing `_requestMediaChannelDescriptions` callback already serves the discovery path.

---

## Self-review notes

- **Spec coverage:** Every section of the spec has at least one task. Frame transformer (Tasks 3–4), every-receiver install (Tasks 5, 7), discovery + debounce + release (Task 6), `ActiveAudioSsrcs` removal (Tasks 1–2), docs (Task 8), regression sweep (Task 9).
- **Type / name consistency:** `GRAudioFrameTransformer` (not `GRSsrcTapTransformer`) used everywhere. Member field `_audioFrameTransformer` everywhere. Constants `kSsrcDiscoveryTimeoutMs`, `kMaxBufferedFramesPerSsrc`, `kMaxConcurrentBufferedSsrcs`, `kDiscoveryRenegotiationDelayMs` defined once and referenced once.
- **Placeholder scan:** No "TBD"/"TODO"/"similar to N" — every code-touching step has the actual code.
- **Test verification:** The test bench T1–T5 are referenced by exact CLI invocations, with the muted-peer invariant called out as the strongest signal for routing regressions. Task 1's intentional regression is explicitly framed as TDD-red so the engineer doesn't think they broke something.
