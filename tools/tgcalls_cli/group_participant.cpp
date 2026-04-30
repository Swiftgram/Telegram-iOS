#include "group_participant.h"

#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdarg>
#include <cstdio>
#include <set>
#include <thread>
#include <unistd.h>

#include "third-party/json11.hpp"

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------

std::chrono::steady_clock::time_point gGroupStartTime = std::chrono::steady_clock::now();
std::atomic<bool> gGroupQuiet{false};

double groupElapsed() {
    auto now = std::chrono::steady_clock::now();
    return std::chrono::duration<double>(now - gGroupStartTime).count();
}

void groupLog(const char* tag, const char* fmt, ...) {
    if (gGroupQuiet) return;
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    fprintf(stderr, "[%7.3f] %s: %s\n", groupElapsed(), tag, buf);
}

// ---------------------------------------------------------------------------
// GroupSineRecorder
// ---------------------------------------------------------------------------

GroupSineRecorder::GroupSineRecorder() {
    buffer_.resize(kFrameSamples * kChannels);
}

tgcalls::AudioFrame GroupSineRecorder::Record() {
    for (size_t i = 0; i < kFrameSamples; ++i) {
        double t = static_cast<double>(phase_) / kSampleRate;
        int16_t sample = static_cast<int16_t>(kAmplitude * std::sin(2.0 * M_PI * kFrequency * t));
        for (size_t ch = 0; ch < kChannels; ++ch) {
            buffer_[i * kChannels + ch] = sample;
        }
        ++phase_;
    }

    tgcalls::AudioFrame frame;
    frame.audio_samples = buffer_.data();
    frame.num_samples = kFrameSamples;
    frame.bytes_per_sample = sizeof(int16_t);
    frame.num_channels = kChannels;
    frame.samples_per_sec = kSampleRate;
    frame.elapsed_time_ms = 0;
    frame.ntp_time_ms = 0;
    return frame;
}

int32_t GroupSineRecorder::WaitForUs() {
    return 10000; // 10ms
}

// ---------------------------------------------------------------------------
// GroupNoOpRenderer
// ---------------------------------------------------------------------------

bool GroupNoOpRenderer::Render(const tgcalls::AudioFrame&) { return true; }

// ---------------------------------------------------------------------------
// SimpleRequestMediaChannelDescriptionTask
// ---------------------------------------------------------------------------

void SimpleRequestMediaChannelDescriptionTask::cancel() {}

// ---------------------------------------------------------------------------
// createParticipant
// ---------------------------------------------------------------------------

std::unique_ptr<ParticipantState> createParticipant(
    int id,
    bool isReference,
    GoInt sfuHandle,
    std::shared_ptr<tgcalls::Threads> threads,
    bool quiet,
    bool video,
    std::vector<std::unique_ptr<ParticipantState>>* allStates
) {
    auto state = std::make_unique<ParticipantState>();
    state->id = id;
    state->isReference = isReference;
    state->logPath = "/tmp/tgcalls_group_p" + std::to_string(id) + "_" + std::to_string(getpid()) + ".log";

    std::string tag = "P" + std::to_string(id);

    auto recorder = std::make_shared<GroupSineRecorder>();
    auto renderer = std::make_shared<GroupNoOpRenderer>();

    ParticipantState* statePtr = state.get();
    GoInt sfuH = sfuHandle;

    tgcalls::GroupInstanceDescriptor descriptor;
    descriptor.threads = threads;
    descriptor.config.need_log = true;
    descriptor.config.logPath = {state->logPath};
    descriptor.networkStateUpdated = [statePtr, tag](tgcalls::GroupNetworkState networkState) {
        groupLog(tag.c_str(), "network state: connected=%s", networkState.isConnected ? "true" : "false");
        statePtr->connected.store(networkState.isConnected);
        if (networkState.isConnected) {
            statePtr->wasConnected.store(true);
        }
    };
    descriptor.audioLevelsUpdated = [statePtr, tag](tgcalls::GroupLevelsUpdate const &update) {
        for (const auto& level : update.updates) {
            if (level.value.level > 0.01f) {
                groupLog(tag.c_str(), "audio level: ssrc=%u level=%.3f voice=%d",
                         level.ssrc, level.value.level, level.value.voice);
            }
            if (level.ssrc != 0 && level.value.level > 0.05f) {
                statePtr->receivedAudio.store(true);
            }
        }
    };
    descriptor.createAudioDeviceModule = tgcalls::FakeAudioDeviceModule::Creator(
        renderer, recorder,
        tgcalls::FakeAudioDeviceModule::Options{.samples_per_sec = 48000, .num_channels = 2}
    );

    descriptor.requestMediaChannelDescriptions = [sfuH, tag, allStates](
        std::vector<uint32_t> const &ssrcs,
        std::function<void(std::vector<tgcalls::MediaChannelDescription> &&)> callback
    ) -> std::shared_ptr<tgcalls::RequestMediaChannelDescriptionTask> {
        std::set<uint32_t> audioSsrcs;
        for (const auto& s : *allStates) {
            if (s->audioSsrc != 0) audioSsrcs.insert(s->audioSsrc);
        }
        std::vector<tgcalls::MediaChannelDescription> descriptions;
        for (uint32_t ssrc : ssrcs) {
            GoInt ownerID = GoSfu_QuerySsrc(sfuH, (GoUint)ssrc);
            bool isAudio = audioSsrcs.count(ssrc) > 0;
            groupLog(tag.c_str(), "requestMediaChannelDescriptions: ssrc=%u -> owner=%lld type=%s",
                     ssrc, (long long)ownerID, isAudio ? "audio" : "video");
            tgcalls::MediaChannelDescription desc;
            desc.type = isAudio ? tgcalls::MediaChannelDescription::Type::Audio
                                : tgcalls::MediaChannelDescription::Type::Video;
            desc.audioSsrc = ssrc;
            desc.userId = ownerID;
            descriptions.push_back(std::move(desc));
        }
        callback(std::move(descriptions));
        return std::make_shared<SimpleRequestMediaChannelDescriptionTask>();
    };

    descriptor.outgoingAudioBitrateKbit = 32;
    descriptor.disableIncomingChannels = false;
    descriptor.useDummyChannel = true;

    // Video configuration
    if (video) {
        auto videoSource = FakeVideoTrackSource::Create(id);
        state->videoSource = videoSource;
        state->endpointId = std::to_string(id);
        descriptor.videoContentType = tgcalls::VideoContentType::Generic;
        descriptor.videoCodecPreferences = {tgcalls::VideoCodecName::H264};
        // Set the outgoing video min bitrate to 600 kbps so the sender's
        // BWE floor is high enough to activate all 3 simulcast layers
        // (audio 32k + L0 min 50k + L1 min 100k + L2 min 300k = 482k).
        // On localhost, delay-based BWE over the loopback pacer has been
        // observed to drift down to ~80 kbps, keeping L2 disabled. Clamping
        // the min forces the encoder to keep L2 producing.
        descriptor.minOutgoingVideoBitrateKbit = 600;
        descriptor.getVideoSource = [videoSource]() -> webrtc::scoped_refptr<webrtc::VideoTrackSourceInterface> {
            return videoSource;
        };

        descriptor.dataChannelMessageReceived = [statePtr, sfuH, tag](std::string const &message) {
            std::string parseErr;
            auto json = json11::Json::parse(message, parseErr);
            if (!parseErr.empty() || !json.is_object()) return;
            auto cls = json["colibriClass"].string_value();
            if (cls != "ActiveVideoSsrcs") return;

            auto ssrcsArray = json["ssrcs"].array_items();
            if (ssrcsArray.empty()) return;

            std::vector<tgcalls::VideoChannelDescription> videoChannels;
            for (const auto& entry : ssrcsArray) {
                std::string endpointId = entry["endpointId"].string_value();
                if (endpointId == statePtr->endpointId) continue;

                {
                    std::lock_guard<std::mutex> lock(statePtr->videoSinksMutex);
                    if (statePtr->videoSinks.count(endpointId) > 0) continue;
                }

                int remoteId = 0;
                if (sscanf(endpointId.c_str(), "%d", &remoteId) != 1) continue;

                char* ssrcsRaw = GoSfu_QueryVideoSsrcs(sfuH, (GoInt)remoteId);
                if (!ssrcsRaw) continue;
                std::string ssrcsJson(ssrcsRaw);
                GoSfu_Free(ssrcsRaw);

                std::string err2;
                auto layers = json11::Json::parse(ssrcsJson, err2);
                if (!err2.empty() || !layers.is_array() || layers.array_items().empty()) continue;

                tgcalls::VideoChannelDescription desc;
                desc.audioSsrc = 0;
                desc.userId = remoteId;
                desc.endpointId = endpointId;
                desc.maxQuality = tgcalls::VideoChannelDescription::Quality::Full;
                desc.minQuality = tgcalls::VideoChannelDescription::Quality::Full;

                tgcalls::MediaSsrcGroup simGroup;
                simGroup.semantics = "SIM";
                for (const auto& layer : layers.array_items()) {
                    uint32_t ssrc = static_cast<uint32_t>(static_cast<int64_t>(layer["ssrc"].number_value()));
                    uint32_t fidSsrc = static_cast<uint32_t>(static_cast<int64_t>(layer["fidSsrc"].number_value()));
                    if (ssrc == 0) continue;
                    simGroup.ssrcs.push_back(ssrc);
                    if (fidSsrc != 0) {
                        tgcalls::MediaSsrcGroup fidGroup;
                        fidGroup.semantics = "FID";
                        fidGroup.ssrcs = {ssrc, fidSsrc};
                        desc.ssrcGroups.push_back(std::move(fidGroup));
                    }
                }
                desc.ssrcGroups.insert(desc.ssrcGroups.begin(), std::move(simGroup));
                videoChannels.push_back(std::move(desc));

                auto sink = std::make_shared<FakeVideoSink>();
                {
                    std::lock_guard<std::mutex> lock(statePtr->videoSinksMutex);
                    statePtr->videoSinks[endpointId] = sink;
                }
                statePtr->instance->addIncomingVideoOutput(
                    endpointId,
                    std::weak_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>>(sink));

                groupLog(tag.c_str(), "ActiveVideoSsrcs: adding video channel for endpoint %s", endpointId.c_str());
            }

            if (!videoChannels.empty()) {
                statePtr->instance->setRequestedVideoChannels(std::move(videoChannels));
            }
        };
    } else {
        descriptor.videoContentType = tgcalls::VideoContentType::None;
    }

    // Create instance
    if (isReference) {
        state->instance = std::make_unique<tgcalls::GroupInstanceReferenceImpl>(std::move(descriptor));
        groupLog(tag.c_str(), "created GroupInstanceReferenceImpl");
    } else {
        state->instance = std::make_unique<tgcalls::GroupInstanceCustomImpl>(std::move(descriptor));
        groupLog(tag.c_str(), "created GroupInstanceCustomImpl");
    }

    // Set connection mode
    state->instance->setConnectionMode(
        tgcalls::GroupConnectionMode::GroupConnectionModeRtc, false, false);

    // Emit join payload
    std::mutex joinMutex;
    std::condition_variable joinCv;
    bool joinReady = false;
    std::string joinJson;
    uint32_t joinSsrc = 0;

    state->instance->emitJoinPayload([&](tgcalls::GroupJoinPayload const &payload) {
        std::lock_guard<std::mutex> lock(joinMutex);
        joinJson = payload.json;
        joinSsrc = payload.audioSsrc;
        joinReady = true;
        joinCv.notify_one();
    });

    {
        std::unique_lock<std::mutex> lock(joinMutex);
        if (!joinCv.wait_for(lock, std::chrono::seconds(5), [&] { return joinReady; })) {
            fprintf(stderr, "Error: emitJoinPayload timed out for participant %d\n", id);
            return nullptr;
        }
    }

    state->audioSsrc = joinSsrc;
    groupLog(tag.c_str(), "join payload ready: ssrc=%u, json=%zu bytes", joinSsrc, joinJson.size());

    // Join SFU
    GoInt iceControlling = isReference ? 0 : 1;
    char* responseRaw = GoSfu_Join(sfuHandle, (GoInt)id, const_cast<char*>(joinJson.c_str()), iceControlling);
    if (!responseRaw) {
        fprintf(stderr, "Error: GoSfu_Join returned null for participant %d\n", id);
        return nullptr;
    }
    std::string response(responseRaw);
    GoSfu_Free(responseRaw);

    if (response.find("\"error\"") != std::string::npos) {
        fprintf(stderr, "Error: GoSfu_Join failed for participant %d: %s\n", id, response.c_str());
        return nullptr;
    }

    groupLog(tag.c_str(), "SFU join response: %zu bytes", response.size());

    state->instance->setJoinResponsePayload(response);
    state->instance->setIsMuted(false);

    groupLog(tag.c_str(), "joined and unmuted");
    return state;
}

// ---------------------------------------------------------------------------
// stopParticipant
// ---------------------------------------------------------------------------

void stopParticipant(ParticipantState* state, GoInt sfuHandle) {
    if (!state || !state->instance) return;

    std::string tag = "P" + std::to_string(state->id);

    // Remove from SFU first so broadcasts go out to remaining participants.
    GoInt rc = GoSfu_Leave(sfuHandle, (GoInt)state->id);
    if (rc != 0) {
        groupLog(tag.c_str(), "GoSfu_Leave returned %lld (may already be removed)", (long long)rc);
    }

    // Stop video source.
    if (state->videoSource) {
        state->videoSource->Stop();
    }

    // Stop instance with timeout. Heap-allocate sync state so the stop callback
    // is safe even if it fires after the 5s timeout (avoids stack-frame UB).
    struct StopState {
        std::mutex mu;
        std::condition_variable cv;
        std::atomic<bool> done{false};
    };
    auto stopState = std::make_shared<StopState>();

    state->instance->stop([stopState]() {
        stopState->done.store(true);
        std::lock_guard<std::mutex> lock(stopState->mu);
        stopState->cv.notify_all();
    });

    {
        std::unique_lock<std::mutex> lock(stopState->mu);
        stopState->cv.wait_for(lock, std::chrono::seconds(5), [&] { return stopState->done.load(); });
    }

    state->instance.reset();

    // Clean up log file.
    unlink(state->logPath.c_str());

    groupLog(tag.c_str(), "stopped and cleaned up");
}

// ---------------------------------------------------------------------------
// validateGroupState
// ---------------------------------------------------------------------------

GroupValidationResult validateGroupState(
    const std::vector<std::unique_ptr<ParticipantState>>& states,
    bool video
) {
    GroupValidationResult result{};
    result.totalParticipants = static_cast<int>(states.size());

    for (const auto& s : states) {
        if (s->wasConnected.load()) result.connectedCount++;
        if (s->receivedAudio.load()) result.audioReceivedCount++;
    }

    if (video) {
        int videoParticipants = 0;
        for (const auto& s : states) {
            if (s->videoSource) videoParticipants++;
        }
        result.videoExpectedPairs = videoParticipants * (videoParticipants - 1);

        for (const auto& s : states) {
            std::lock_guard<std::mutex> lock(s->videoSinksMutex);
            for (const auto& [endpointId, sink] : s->videoSinks) {
                int frames = sink->frameCount();
                if (frames > 0) {
                    result.videoReceivedPairs++;
                }
                groupLog("Validate", "P%d <- endpoint %s: %d video frames (%dx%d)",
                         s->id, endpointId.c_str(), frames,
                         sink->lastWidth(), sink->lastHeight());
            }
        }
    }

    result.success = (result.connectedCount == result.totalParticipants &&
                      result.audioReceivedCount == result.totalParticipants);
    if (video && result.videoExpectedPairs > 0) {
        result.success = result.success && (result.videoReceivedPairs >= result.videoExpectedPairs);
    }

    return result;
}

// ---------------------------------------------------------------------------
// printGroupSummary
// ---------------------------------------------------------------------------

bool printGroupSummary(
    int customParticipants,
    int referenceParticipants,
    int duration,
    bool video,
    const GroupValidationResult& result,
    bool anyFailed
) {
    bool success = result.success && !anyFailed;

    printf("\n=== Group Call Summary ===\n");
    printf("Custom participants:    %d\n", customParticipants);
    printf("Reference participants: %d\n", referenceParticipants);
    printf("Total participants:     %d\n", result.totalParticipants);
    printf("Duration:               %ds\n", duration);
    printf("SFU:                    Go/Pion (in-process)\n");
    printf("Connected:              %d/%d\n", result.connectedCount, result.totalParticipants);
    printf("Audio received:         %d/%d\n", result.audioReceivedCount, result.totalParticipants);
    if (video) {
        printf("Video received:         %d/%d\n", result.videoReceivedPairs, result.videoExpectedPairs);
    }
    printf("Result:                 %s\n", success ? "SUCCESS" : "FAILED");

    return success;
}
