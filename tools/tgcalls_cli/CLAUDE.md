# tgcalls CLI Test Tool

In-process test harness for tgcalls. See the root `CLAUDE.md` for build instructions, top-level CLI usage, and the CLI options reference.

## Supported Versions

| Version | Implementation | Notes |
|---|---|---|
| `14.0.0` | `InstanceV2CompatImpl` | WebRTC PeerConnection + V2Impl signaling. Cross-version interop with 7.0.0–13.0.0 |
| `13.0.0` (default) | `InstanceV2Impl` | Also: 7.0.0, 8.0.0, 9.0.0, 12.0.0 |
| `11.0.0` | `InstanceV2ReferenceImpl` | Also: 10.0.0. Uses WebRTC PeerConnection |
| `5.0.0` | `InstanceImpl` (v1) | Also: 2.7.7. Legacy |

## Architecture (P2P/Reflector)
- Two `tgcalls::Instance` objects (caller + callee) created via `Meta::Create(version, ...)`
- Signaling bridged via `SignalingBridge` with configurable drop rate and delay
- `FakeAudioDeviceModule` with `SineRecorder` (440Hz tone) and `NoOpRenderer` (audio discarded; validation via BWE)
- `FakeInterface` platform implementation (pure C++, no iOS/ObjC deps)
- Stats log validation: both caller and callee write `config.statsLogPath` with bitrate records; non-empty log with at least one non-zero BWE value is a success condition
- On failure, full tgcalls internal logs (caller + callee) are dumped to stdout via `config.logPath`

## Architecture (Group)
- N participants using `GroupInstanceCustomImpl` and/or `GroupInstanceReferenceImpl` connect to an in-process Go SFU
- SFU uses Pion's low-level APIs (pion/ice, pion/dtls, pion/srtp, pion/sctp) — NOT PeerConnection
- ICE: lite mode, loopback-only, UDP host candidates on 127.0.0.1. SFU uses `Dial` (controlling) for CustomImpl clients and `Accept` (controlled) for PeerConnection clients
- DTLS: SFU acts as DTLS client (setup=active); GroupNetworkManager hardcodes SSL_SERVER for the tgcalls client
- SRTP: AES-256-GCM (negotiated via DTLS-SRTP; GroupNetworkManager requires GCM suites)
- SCTP: over DTLS, accepts data channel from client, reads Colibri messages, sends `ActiveAudioSsrcs` and `ActiveVideoSsrcs` notifications
- RTP forwarding: audio RTP forwarded to all others unconditionally; video RTP forwarded only to receivers that have requested video from that sender (via `ReceiverVideoConstraints`)
- SSRC tracking: SFU maintains `ssrcRegistry map[uint32]ssrcInfo` with kind (audio/video/video-rtx) and simulcast layer index, exposed via `GoSfu_QuerySsrc` and `GoSfu_QueryVideoSsrcs` CGo exports
- SSRC discovery: SFU broadcasts `ActiveAudioSsrcs` and `ActiveVideoSsrcs` over data channel when participants connect
- Video SSRC groups: parsed from join payload `"ssrc-groups"` field (SIM + FID semantics), stored per participant
- Colibri video constraints: SFU parses `ReceiverVideoConstraints` from receivers, sends `SenderVideoConstraints` back to senders with `idealHeight`, and sends proactive PLI to trigger keyframes when a receiver first requests video
- RTCP feedback: SFU demuxes SRTCP from the shared ICE transport (RFC 5761: byte[1] >= 200 && < 224), decrypts with per-participant SRTCP contexts, parses PLI/FIR, and forwards as new PLI to the sender. NACK is terminated (not forwarded).
- Audio validation: `audioLevelsUpdated` callback tracks remote audio levels; success requires every participant to receive audio from at least one other participant (remote SSRC != 0, level > 0.05). The 440Hz sine tone arrives at ~0.126 level after SFU forwarding.
- Video validation: `FakeVideoSink` (implements `rtc::VideoSinkInterface<VideoFrame>`) counts decoded frames per remote endpoint; success requires every participant to receive ≥1 frame from every other
- Video signaling flow: SFU broadcasts `ActiveVideoSsrcs` over data channel → `dataChannelMessageReceived` callback fires in the app → app calls `setRequestedVideoChannels` → CustomImpl creates `IncomingVideoChannel` / ReferenceImpl adds recvonly video transceiver → both send `ReceiverVideoConstraints` → SFU sends `SenderVideoConstraints` + proactive PLI → sender produces keyframe → receiver decodes
- `dataChannelMessageReceived` callback: added to `GroupInstanceDescriptor`, forwards all incoming Colibri data channel messages to the application. Used by the CLI test tool to react to `ActiveVideoSsrcs` and dynamically set up video channels — mirrors the real Telegram app's reactive flow
- `FakeAudioDeviceModule` with `SineRecorder` (440Hz tone) and `NoOpRenderer` — same as P2P mode
- `FakeVideoTrackSource` generates 1280x720 I420 frames at 30fps with per-participant color tint and frame counter (720p needed for 3 simulcast layers; 640x360 only allows 2 per WebRTC's `kSimulcastFormats`)
- Group mode source: `tools/tgcalls_cli/group_mode.cpp`
