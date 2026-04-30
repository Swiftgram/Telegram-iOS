#pragma once

#include <atomic>
#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <vector>

#include "group/GroupInstanceCustomImpl.h"
#include "group/GroupInstanceImpl.h"
#include "group/GroupInstanceReferenceImpl.h"
#include "FakeAudioDeviceModule.h"
#include "StaticThreads.h"
#include "AudioFrame.h"
#include "fake_video_source.h"
#include "fake_video_sink.h"

// CGo header
#include "tools/go_sfu/go_sfu.h"

// ---------------------------------------------------------------------------
// Logging helpers
// ---------------------------------------------------------------------------

extern std::chrono::steady_clock::time_point gGroupStartTime;
extern std::atomic<bool> gGroupQuiet;

double groupElapsed();
void groupLog(const char* tag, const char* fmt, ...);

// ---------------------------------------------------------------------------
// GroupSineRecorder - generates 440 Hz sine tone
// ---------------------------------------------------------------------------

class GroupSineRecorder : public tgcalls::FakeAudioDeviceModule::Recorder {
public:
    GroupSineRecorder();
    tgcalls::AudioFrame Record() override;
    int32_t WaitForUs() override;

private:
    static constexpr size_t kSampleRate = 48000;
    static constexpr size_t kChannels = 2;
    static constexpr size_t kFrameSamples = 480;
    static constexpr double kFrequency = 440.0;
    static constexpr double kAmplitude = 3000.0;

    std::vector<int16_t> buffer_;
    uint64_t phase_ = 0;
};

// ---------------------------------------------------------------------------
// GroupNoOpRenderer - discards received audio
// ---------------------------------------------------------------------------

class GroupNoOpRenderer : public tgcalls::FakeAudioDeviceModule::Renderer {
public:
    bool Render(const tgcalls::AudioFrame&) override;
};

// ---------------------------------------------------------------------------
// SimpleRequestMediaChannelDescriptionTask
// ---------------------------------------------------------------------------

class SimpleRequestMediaChannelDescriptionTask : public tgcalls::RequestMediaChannelDescriptionTask {
public:
    void cancel() override;
};

// ---------------------------------------------------------------------------
// ParticipantState
// ---------------------------------------------------------------------------

struct ParticipantState {
    int id;
    bool isReference;
    std::unique_ptr<tgcalls::GroupInstanceInterface> instance;
    std::atomic<bool> connected{false};
    std::atomic<bool> wasConnected{false};
    std::atomic<bool> receivedAudio{false};
    uint32_t audioSsrc{0};
    std::string logPath;

    // Video fields
    std::string endpointId;
    rtc::scoped_refptr<FakeVideoTrackSource> videoSource;
    std::mutex videoSinksMutex;
    std::map<std::string, std::shared_ptr<FakeVideoSink>> videoSinks;
};

// ---------------------------------------------------------------------------
// GroupValidationResult
// ---------------------------------------------------------------------------

struct GroupValidationResult {
    int totalParticipants;
    int connectedCount;
    int audioReceivedCount;
    int videoReceivedPairs;
    int videoExpectedPairs;
    bool success;
};

// ---------------------------------------------------------------------------
// Participant lifecycle functions
// ---------------------------------------------------------------------------

// Creates a fully initialized participant: builds descriptor, creates instance,
// joins SFU, sets join response, unmutes. Returns nullptr on failure.
std::unique_ptr<ParticipantState> createParticipant(
    int id,
    bool isReference,
    GoInt sfuHandle,
    std::shared_ptr<tgcalls::Threads> threads,
    bool quiet,
    bool video,
    std::vector<std::unique_ptr<ParticipantState>>* allStates
);

// Clean teardown: GoSfu_Leave, stop video, stop instance, reset.
void stopParticipant(ParticipantState* state, GoInt sfuHandle);

// Validates group state: connection, audio, video. Returns result struct.
GroupValidationResult validateGroupState(
    const std::vector<std::unique_ptr<ParticipantState>>& states,
    bool video
);

// Prints a group call summary to stdout. Returns the success boolean.
bool printGroupSummary(
    int customParticipants,
    int referenceParticipants,
    int duration,
    bool video,
    const GroupValidationResult& result,
    bool anyFailed
);
