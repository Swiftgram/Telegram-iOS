#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <memory>
#include <mutex>
#include <random>
#include <fstream>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

#include "group_mode.h"
#include "group_churn_mode.h"
#include "Instance.h"
#include "FakeAudioDeviceModule.h"
#include "VideoCaptureInterface.h"
#include "v2/InstanceV2Impl.h"
#include "v2/InstanceV2CompatImpl.h"
#include "v2/InstanceV2ReferenceImpl.h"

#include "modules/audio_device/include/audio_device.h"
#include "api/task_queue/task_queue_factory.h"

// Stub: AudioDeviceModule::Create is referenced by InstanceV2Impl as a fallback
// but never called when createAudioDeviceModule is provided in the Descriptor.
namespace webrtc {
rtc::scoped_refptr<AudioDeviceModule> AudioDeviceModule::Create(
    AudioDeviceModule::AudioLayer audio_layer,
    TaskQueueFactory* task_queue_factory) {
    return nullptr;
}
} // namespace webrtc

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static auto gStartTime = std::chrono::steady_clock::now();

static double elapsed() {
    auto now = std::chrono::steady_clock::now();
    return std::chrono::duration<double>(now - gStartTime).count();
}

static bool gQuiet = false;

static void logMsg(const char* role, const char* fmt, ...) {
    if (gQuiet) return;
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    fprintf(stderr, "[%7.3f] %s: %s\n", elapsed(), role, buf);
}

static const char* stateName(tgcalls::State s) {
    switch (s) {
        case tgcalls::State::WaitInit:    return "WaitInit";
        case tgcalls::State::WaitInitAck: return "WaitInitAck";
        case tgcalls::State::Established: return "Established";
        case tgcalls::State::Failed:      return "Failed";
        case tgcalls::State::Reconnecting:return "Reconnecting";
    }
    return "Unknown";
}

static std::string hexEncode(const std::array<uint8_t, 16>& data) {
    char buf[33];
    for (size_t i = 0; i < 16; ++i) {
        snprintf(buf + i * 2, 3, "%02x", data[i]);
    }
    return std::string(buf, 32);
}

static tgcalls::RtcServer makeReflectorServer(const std::string& host, uint16_t port,
                                                const std::array<uint8_t, 16>& peerTag) {
    tgcalls::RtcServer server;
    server.id = 1;
    server.host = host;
    server.port = port;
    server.login = "reflector";
    server.password = hexEncode(peerTag);
    server.isTurn = true;
    server.isTcp = false;
    return server;
}

// ---------------------------------------------------------------------------
// SineRecorder - generates 440 Hz sine tone
// ---------------------------------------------------------------------------

class SineRecorder : public tgcalls::FakeAudioDeviceModule::Recorder {
public:
    SineRecorder() {
        buffer_.resize(kFrameSamples * kChannels);
    }

    tgcalls::AudioFrame Record() override {
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

    int32_t WaitForUs() override {
        return 10000; // 10ms
    }

private:
    static constexpr size_t kSampleRate = 48000;
    static constexpr size_t kChannels = 2;
    static constexpr size_t kFrameSamples = 480; // 10ms at 48kHz
    static constexpr double kFrequency = 440.0;
    static constexpr double kAmplitude = 3000.0;

    std::vector<int16_t> buffer_;
    uint64_t phase_ = 0;
};

// ---------------------------------------------------------------------------
// NoOpRenderer - discards received audio (validation is done via BWE stats)
// ---------------------------------------------------------------------------

class NoOpRenderer : public tgcalls::FakeAudioDeviceModule::Renderer {
public:
    bool Render(const tgcalls::AudioFrame&) override { return true; }
};

// ---------------------------------------------------------------------------
// SignalingBridge
// ---------------------------------------------------------------------------

struct SignalingBridge {
    std::mutex mutex;
    std::shared_ptr<tgcalls::Instance> caller;
    std::shared_ptr<tgcalls::Instance> callee;

    // Network simulation
    double dropRate = 0.0;
    int delayMinMs = 0;
    int delayMaxMs = 0;
    std::mt19937 rng{std::random_device{}()};

    void deliver(const char* fromRole, const std::vector<uint8_t>& data,
                 std::shared_ptr<tgcalls::Instance>& target) {
        if (dropRate > 0.0) {
            std::uniform_real_distribution<double> dropDist(0.0, 1.0);
            if (dropDist(rng) < dropRate) {
                logMsg(fromRole, "signaling DROPPED (%zu bytes)", data.size());
                return;
            }
        }
        if (delayMaxMs > 0) {
            std::uniform_int_distribution<int> delayDist(delayMinMs, delayMaxMs);
            int delayMs = delayDist(rng);
            if (delayMs > 0) {
                logMsg(fromRole, "signaling delayed %dms (%zu bytes)", delayMs, data.size());
                auto dataCopy = data;
                auto targetWeak = std::weak_ptr<tgcalls::Instance>(target);
                std::thread([dataCopy, targetWeak, delayMs]() {
                    std::this_thread::sleep_for(std::chrono::milliseconds(delayMs));
                    if (auto t = targetWeak.lock()) {
                        t->receiveSignalingData(dataCopy);
                    }
                }).detach();
                return;
            }
        }
        if (target) {
            target->receiveSignalingData(data);
        }
    }
};

// ---------------------------------------------------------------------------
// CallState
// ---------------------------------------------------------------------------

struct CallState {
    std::mutex mutex;
    tgcalls::State callerState = tgcalls::State::WaitInit;
    tgcalls::State calleeState = tgcalls::State::WaitInit;
    double establishedAt = -1.0;
    std::vector<std::string> errors;
};

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

int main(int argc, char* argv[]) {
    int duration = 10;
    std::string mode;
    std::string reflectorAddr;
    std::string reflectorList;
    std::string version = "13.0.0";
    std::string version2;
    double dropRate = 0.0;
    int delayMinMs = 0;
    int delayMaxMs = 0;
    int participants = 3;
    int referenceParticipants = 0;
    bool enableVideo = false;
    int churnCycles = 100;
    std::string networkScenario;

    for (int i = 1; i < argc; ++i) {
        if (std::string(argv[i]) == "--duration" && i + 1 < argc) {
            duration = std::atoi(argv[++i]);
        } else if (std::string(argv[i]) == "--quiet") {
            gQuiet = true;
        } else if (std::string(argv[i]) == "--mode" && i + 1 < argc) {
            mode = argv[++i];
        } else if (std::string(argv[i]) == "--reflector" && i + 1 < argc) {
            reflectorAddr = argv[++i];
        } else if (std::string(argv[i]) == "--reflector-list" && i + 1 < argc) {
            reflectorList = argv[++i];
        } else if (std::string(argv[i]) == "--drop-rate" && i + 1 < argc) {
            dropRate = std::atof(argv[++i]);
        } else if (std::string(argv[i]) == "--version" && i + 1 < argc) {
            version = argv[++i];
        } else if (std::string(argv[i]) == "--version2" && i + 1 < argc) {
            version2 = argv[++i];
        } else if (std::string(argv[i]) == "--participants" && i + 1 < argc) {
            participants = std::atoi(argv[++i]);
        } else if (std::string(argv[i]) == "--reference-participants" && i + 1 < argc) {
            referenceParticipants = std::atoi(argv[++i]);
        } else if (std::string(argv[i]) == "--video") {
            enableVideo = true;
        } else if (std::string(argv[i]) == "--churn-cycles" && i + 1 < argc) {
            churnCycles = std::atoi(argv[++i]);
        } else if (std::string(argv[i]) == "--network-scenario" && i + 1 < argc) {
            networkScenario = argv[++i];
        } else if (std::string(argv[i]) == "--delay" && i + 1 < argc) {
            std::string delayStr = argv[++i];
            auto dashPos = delayStr.find('-');
            if (dashPos != std::string::npos) {
                delayMinMs = std::atoi(delayStr.substr(0, dashPos).c_str());
                delayMaxMs = std::atoi(delayStr.substr(dashPos + 1).c_str());
            } else {
                delayMinMs = 0;
                delayMaxMs = std::atoi(delayStr.c_str());
            }
        }
    }

    if (version2.empty()) {
        version2 = version;
    }

    // If --reflector-list provided, pick one at random
    if (!reflectorList.empty()) {
        std::vector<std::string> addrs;
        size_t pos = 0;
        while (pos < reflectorList.size()) {
            size_t next = reflectorList.find(',', pos);
            if (next == std::string::npos) next = reflectorList.size();
            std::string addr = reflectorList.substr(pos, next - pos);
            if (!addr.empty()) addrs.push_back(addr);
            pos = next + 1;
        }
        if (addrs.empty()) {
            fprintf(stderr, "Error: --reflector-list is empty\n");
            return 1;
        }
        std::random_device rd;
        std::mt19937 rng(rd());
        std::uniform_int_distribution<size_t> dist(0, addrs.size() - 1);
        reflectorAddr = addrs[dist(rng)];
        if (reflectorAddr.rfind(':') == std::string::npos) {
            std::uniform_int_distribution<int> portDist(596, 599);
            reflectorAddr += ":" + std::to_string(portDist(rng));
        }
        if (mode.empty()) mode = "reflector";
    }

    // Validate --mode
    if (mode.empty()) {
        fprintf(stderr, "Error: --mode is required (p2p, reflector, group, or group-churn)\n");
        return 1;
    }
    if (mode != "p2p" && mode != "reflector" && mode != "group" && mode != "group-churn") {
        fprintf(stderr, "Error: --mode must be 'p2p', 'reflector', 'group', or 'group-churn'\n");
        return 1;
    }

    // Group mode: dispatch to separate implementation
    if (mode == "group") {
        return runGroupMode(participants, referenceParticipants, duration, gQuiet, enableVideo, networkScenario);
    }
    if (mode == "group-churn") {
        return runGroupChurnMode(participants, referenceParticipants, duration, gQuiet, enableVideo, churnCycles);
    }
    if (mode == "reflector" && reflectorAddr.empty()) {
        fprintf(stderr, "Error: --reflector host:port is required with --mode reflector\n");
        return 1;
    }
    if (mode == "p2p" && !reflectorAddr.empty()) {
        fprintf(stderr, "Error: --reflector cannot be used with --mode p2p\n");
        return 1;
    }

    // Parse reflector address
    std::string reflectorHost;
    uint16_t reflectorPort = 0;
    if (mode == "reflector") {
        auto colonPos = reflectorAddr.rfind(':');
        if (colonPos == std::string::npos) {
            fprintf(stderr, "Error: --reflector must be in host:port format\n");
            return 1;
        }
        reflectorHost = reflectorAddr.substr(0, colonPos);
        reflectorPort = static_cast<uint16_t>(std::atoi(reflectorAddr.substr(colonPos + 1).c_str()));
        if (reflectorPort == 0) {
            fprintf(stderr, "Error: invalid reflector port\n");
            return 1;
        }
    }

    // Generate peer tags for reflector mode
    std::array<uint8_t, 16> callerPeerTag{};
    std::array<uint8_t, 16> calleePeerTag{};
    if (mode == "reflector") {
        std::random_device rd;
        std::mt19937 rng(rd());
        std::uniform_int_distribution<int> dist(0, 255);
        for (auto& b : callerPeerTag) {
            b = static_cast<uint8_t>(dist(rng));
        }
        calleePeerTag = callerPeerTag;
        callerPeerTag[0] = 0x00;
        calleePeerTag[0] = 0x01;
    }

    // Register implementations
    tgcalls::Register<tgcalls::InstanceV2Impl>();
    tgcalls::Register<tgcalls::InstanceV2CompatImpl>();
    tgcalls::Register<tgcalls::InstanceV2ReferenceImpl>();

    // Create shared encryption key
    auto keyData = std::make_shared<std::array<uint8_t, 256>>();
    {
        std::mt19937 rng(42);
        std::uniform_int_distribution<int> dist(0, 255);
        for (auto& b : *keyData) {
            b = static_cast<uint8_t>(dist(rng));
        }
    }

    // Bridge and state
    auto bridge = std::make_shared<SignalingBridge>();
    bridge->dropRate = dropRate;
    bridge->delayMinMs = delayMinMs;
    bridge->delayMaxMs = delayMaxMs;
    auto callState = std::make_shared<CallState>();

    // Audio components
    auto callerRecorder = std::make_shared<SineRecorder>();
    auto callerRenderer = std::make_shared<NoOpRenderer>();
    auto calleeRecorder = std::make_shared<SineRecorder>();
    auto calleeRenderer = std::make_shared<NoOpRenderer>();

    // Stats log paths (per-process to avoid collisions in parallel runs)
    std::string callerStatsPath = "/tmp/tgcalls_cli_caller_" + std::to_string(getpid()) + ".json";
    std::string calleeStatsPath = "/tmp/tgcalls_cli_callee_" + std::to_string(getpid()) + ".json";

    // --- Caller descriptor ---
    auto callerDesc = (tgcalls::Descriptor){
        .version = version,
        .config = {
            .initializationTimeout = 10.0,
            .receiveTimeout = 10.0,
            .enableP2P = (mode == "p2p"),
            .statsLogPath = {callerStatsPath},
        },
        .rtcServers = (mode == "reflector")
            ? std::vector<tgcalls::RtcServer>{makeReflectorServer(reflectorHost, reflectorPort, callerPeerTag)}
            : std::vector<tgcalls::RtcServer>{},
        .encryptionKey = tgcalls::EncryptionKey(keyData, true),
        .stateUpdated = [callState](tgcalls::State state) {
            logMsg("Caller", "state -> %s", stateName(state));
            std::lock_guard<std::mutex> lock(callState->mutex);
            callState->callerState = state;
            if (state == tgcalls::State::Established && callState->establishedAt < 0) {
                callState->establishedAt = elapsed();
            }
            if (state == tgcalls::State::Failed) {
                callState->errors.push_back("Caller entered Failed state");
            }
        },
        .signalingDataEmitted = [bridge](const std::vector<uint8_t>& data) {
            logMsg("Caller", "signaling data emitted (%zu bytes)", data.size());
            std::lock_guard<std::mutex> lock(bridge->mutex);
            bridge->deliver("Caller", data, bridge->callee);
        },
        .createAudioDeviceModule = tgcalls::FakeAudioDeviceModule::Creator(
            callerRenderer, callerRecorder,
            tgcalls::FakeAudioDeviceModule::Options{.samples_per_sec = 48000, .num_channels = 2}
        ),
    };

    // --- Callee descriptor ---
    auto calleeDesc = (tgcalls::Descriptor){
        .version = version2,
        .config = {
            .initializationTimeout = 10.0,
            .receiveTimeout = 10.0,
            .enableP2P = (mode == "p2p"),
            .statsLogPath = {calleeStatsPath},
        },
        .rtcServers = (mode == "reflector")
            ? std::vector<tgcalls::RtcServer>{makeReflectorServer(reflectorHost, reflectorPort, calleePeerTag)}
            : std::vector<tgcalls::RtcServer>{},
        .encryptionKey = tgcalls::EncryptionKey(keyData, false),
        .stateUpdated = [callState](tgcalls::State state) {
            logMsg("Callee", "state -> %s", stateName(state));
            std::lock_guard<std::mutex> lock(callState->mutex);
            callState->calleeState = state;
            if (state == tgcalls::State::Established && callState->establishedAt < 0) {
                callState->establishedAt = elapsed();
            }
            if (state == tgcalls::State::Failed) {
                callState->errors.push_back("Callee entered Failed state");
            }
        },
        .signalingDataEmitted = [bridge](const std::vector<uint8_t>& data) {
            logMsg("Callee", "signaling data emitted (%zu bytes)", data.size());
            std::lock_guard<std::mutex> lock(bridge->mutex);
            bridge->deliver("Callee", data, bridge->caller);
        },
        .createAudioDeviceModule = tgcalls::FakeAudioDeviceModule::Creator(
            calleeRenderer, calleeRecorder,
            tgcalls::FakeAudioDeviceModule::Options{.samples_per_sec = 48000, .num_channels = 2}
        ),
    };

    // Create instances
    auto callerInstance = std::shared_ptr<tgcalls::Instance>(
        tgcalls::Meta::Create(version, std::move(callerDesc)).release());
    if (!callerInstance) {
        fprintf(stderr, "Error: unknown version '%s'\n", version.c_str());
        return 1;
    }
    logMsg("Caller", "created (version %s)", version.c_str());

    auto calleeInstance = std::shared_ptr<tgcalls::Instance>(
        tgcalls::Meta::Create(version2, std::move(calleeDesc)).release());
    if (!calleeInstance) {
        fprintf(stderr, "Error: unknown callee version '%s'\n", version2.c_str());
        return 1;
    }
    logMsg("Callee", "created (version %s)", version2.c_str());

    // Wire bridge
    {
        std::lock_guard<std::mutex> lock(bridge->mutex);
        bridge->caller = callerInstance;
        bridge->callee = calleeInstance;
    }

    logMsg("Main", "sleeping for %d seconds...", duration);
    std::this_thread::sleep_for(std::chrono::seconds(duration));

    // Stop both instances
    logMsg("Main", "stopping instances...");

    std::atomic<int> stopCount{0};
    std::mutex stopMutex;
    std::condition_variable stopCv;

    auto onStopped = [&](const char* role) {
        return [&, role](tgcalls::FinalState) {
            logMsg(role, "stopped");
            stopCount.fetch_add(1);
            std::lock_guard<std::mutex> lock(stopMutex);
            stopCv.notify_all();
        };
    };

    callerInstance->stop(onStopped("Caller"));
    calleeInstance->stop(onStopped("Callee"));

    // Wait for both stop callbacks (up to 5 seconds)
    {
        std::unique_lock<std::mutex> lock(stopMutex);
        stopCv.wait_for(lock, std::chrono::seconds(5), [&] {
            return stopCount.load() >= 2;
        });
    }

    // Release instances — clear bridge first to prevent signaling during teardown
    {
        std::lock_guard<std::mutex> lock(bridge->mutex);
        bridge->caller.reset();
        bridge->callee.reset();
    }
    callerInstance.reset();
    calleeInstance.reset();

    // Read stats logs: count bitrate records and check for non-zero BWE
    struct StatsResult {
        int bitrateRecords = 0;
        bool hasNonZeroBwe = false;
    };
    auto parseStatsLog = [](const std::string& path) -> StatsResult {
        StatsResult result;
        std::ifstream f(path);
        if (!f.is_open()) return result;
        std::string content((std::istreambuf_iterator<char>(f)),
                             std::istreambuf_iterator<char>());
        size_t pos = 0;
        while ((pos = content.find("\"b\":", pos)) != std::string::npos) {
            pos += 4;
            result.bitrateRecords++;
            // Parse the integer value after "b":
            int val = std::atoi(content.c_str() + pos);
            if (val > 0) {
                result.hasNonZeroBwe = true;
            }
        }
        return result;
    };

    auto callerStats = parseStatsLog(callerStatsPath);
    auto calleeStats = parseStatsLog(calleeStatsPath);
    unlink(callerStatsPath.c_str());
    unlink(calleeStatsPath.c_str());

    // Print summary
    {
        std::lock_guard<std::mutex> lock(callState->mutex);

        bool established = (callState->establishedAt >= 0);

        printf("\n=== Call Summary ===\n");
        printf("Duration:          %ds\n", duration);
        if (dropRate > 0.0 || delayMaxMs > 0) {
            printf("Signaling:         drop=%.0f%% delay=%d-%dms\n",
                   dropRate * 100.0, delayMinMs, delayMaxMs);
        }
        if (mode == "reflector") {
            printf("Mode:              reflector (%s:%d)\n", reflectorHost.c_str(), reflectorPort);
        } else {
            printf("Mode:              p2p\n");
        }
        printf("Caller state:      %s\n", stateName(callState->callerState));
        printf("Callee state:      %s\n", stateName(callState->calleeState));
        if (callState->establishedAt >= 0) {
            printf("Call established:  yes (at %.3fs)\n", callState->establishedAt);
        } else {
            printf("Call established:  no\n");
        }
        bool bweNonZero = callerStats.hasNonZeroBwe && calleeStats.hasNonZeroBwe;

        printf("Stats log:         caller=%d callee=%d bitrate records\n",
               callerStats.bitrateRecords, calleeStats.bitrateRecords);
        printf("BWE non-zero:      %s\n", bweNonZero ? "yes" : "no");

        bool statsCollected = (callerStats.bitrateRecords > 0 && calleeStats.bitrateRecords > 0);

        if (callState->errors.empty()) {
            printf("Errors:            none\n");
        } else {
            printf("Errors:\n");
            for (const auto& err : callState->errors) {
                printf("  - %s\n", err.c_str());
            }
        }

        // Use _exit() to skip static destruction. ThreadLocalObject's destructor
        // posts fire-and-forget cleanup tasks to the tgcalls media thread. If we
        // return normally, static destruction tears down the StaticThreads thread
        // pool while those tasks may still be executing, causing "pure virtual
        // function called" when a half-destroyed object's vtable is accessed.
        fflush(stdout);
        fflush(stderr);
        _exit(established && statsCollected && bweNonZero ? 0 : 1);
    }
}
