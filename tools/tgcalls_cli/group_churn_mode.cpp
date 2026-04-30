#include "group_churn_mode.h"
#include "group_participant.h"

#include <chrono>
#include <cstdio>
#include <thread>
#include <unistd.h>

// CGo header
#include "tools/go_sfu/go_sfu.h"

int runGroupChurnMode(
    int customParticipants,
    int referenceParticipants,
    int duration,
    bool quiet,
    bool video,
    int churnCycles
) {
    gGroupQuiet = quiet;
    gGroupStartTime = std::chrono::steady_clock::now();

    int baseCount = customParticipants + referenceParticipants;
    if (baseCount < 2) {
        fprintf(stderr, "Error: need at least 2 base participants total\n");
        return 1;
    }

    groupLog("Churn", "initializing Go SFU...");

    int rc = GoSfu_Init();
    if (rc != 0) {
        fprintf(stderr, "Error: GoSfu_Init failed with %d\n", rc);
        return 1;
    }

    GoInt sfuHandle = GoSfu_Create();
    if (sfuHandle <= 0) {
        fprintf(stderr, "Error: GoSfu_Create failed\n");
        return 1;
    }

    groupLog("Churn", "SFU handle=%lld, base=%d (custom=%d, ref=%d), cycles=%d, video=%s",
             (long long)sfuHandle, baseCount, customParticipants, referenceParticipants,
             churnCycles, video ? "yes" : "no");

    auto threads = tgcalls::StaticThreads::getThreads();

    // --- Phase 1: Create base group ---
    groupLog("Churn", "creating base group...");
    std::vector<std::unique_ptr<ParticipantState>> baseStates;
    bool anyFailed = false;

    for (int i = 0; i < baseCount; ++i) {
        bool isReference = (i >= customParticipants);
        auto state = createParticipant(i, isReference, sfuHandle, threads, quiet, video, &baseStates);
        if (!state) {
            anyFailed = true;
            continue;
        }
        baseStates.push_back(std::move(state));
    }

    // Wait for all base participants to connect
    groupLog("Churn", "waiting for base group connections...");
    auto waitStart = std::chrono::steady_clock::now();
    while (std::chrono::steady_clock::now() - waitStart < std::chrono::seconds(15)) {
        int connectedCount = 0;
        for (const auto& s : baseStates) {
            if (s->wasConnected.load()) connectedCount++;
        }
        if (connectedCount == (int)baseStates.size()) {
            groupLog("Churn", "all %d base participants connected", (int)baseStates.size());
            break;
        }
        groupLog("Churn", "base connected: %d/%d", connectedCount, (int)baseStates.size());
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }

    // Wait for audio to flow in base group
    groupLog("Churn", "waiting for base group audio...");
    waitStart = std::chrono::steady_clock::now();
    while (std::chrono::steady_clock::now() - waitStart < std::chrono::seconds(10)) {
        int audioCount = 0;
        for (const auto& s : baseStates) {
            if (s->receivedAudio.load()) audioCount++;
        }
        if (audioCount == (int)baseStates.size()) {
            groupLog("Churn", "all %d base participants receiving audio", (int)baseStates.size());
            break;
        }
        groupLog("Churn", "base audio: %d/%d", audioCount, (int)baseStates.size());
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }

    // --- Phase 2: Churn loop ---
    groupLog("Churn", "starting churn: %d cycles", churnCycles);
    int nextId = baseCount;
    int completedCycles = 0;

    for (int cycle = 0; cycle < churnCycles; ++cycle) {
        bool isReference = (cycle % 2 == 1);
        int churnId = nextId++;

        auto churner = createParticipant(churnId, isReference, sfuHandle, threads, quiet, video, &baseStates);
        if (!churner) {
            groupLog("Churn", "cycle %d: createParticipant failed for id=%d", cycle, churnId);
            anyFailed = true;
            continue;
        }

        // Wait briefly for connection (up to 3s)
        auto connStart = std::chrono::steady_clock::now();
        while (std::chrono::steady_clock::now() - connStart < std::chrono::seconds(3)) {
            if (churner->wasConnected.load()) break;
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }

        if (!churner->wasConnected.load()) {
            groupLog("Churn", "cycle %d: churner %d did not connect (continuing anyway)", cycle, churnId);
        }

        // Leave
        stopParticipant(churner.get(), sfuHandle);
        completedCycles++;

        if ((cycle + 1) % 10 == 0) {
            groupLog("Churn", "progress: %d/%d cycles completed", cycle + 1, churnCycles);
        }
    }

    groupLog("Churn", "churn complete: %d/%d cycles succeeded", completedCycles, churnCycles);

    // --- Phase 3: Stabilize and validate ---
    groupLog("Churn", "stabilizing for %d seconds...", duration);
    std::this_thread::sleep_for(std::chrono::seconds(duration));

    auto result = validateGroupState(baseStates, video);

    // --- Phase 4: Teardown ---
    groupLog("Churn", "stopping base participants...");

    // Stop video sources
    for (auto& s : baseStates) {
        if (s->videoSource) {
            s->videoSource->Stop();
        }
    }

    // Stop instances
    std::atomic<int> stopCount{0};
    std::mutex stopMutex;
    std::condition_variable stopCv;

    for (const auto& s : baseStates) {
        if (s->instance) {
            int pid_local = s->id;
            s->instance->stop([&stopCount, &stopMutex, &stopCv, pid_local]() {
                groupLog("Churn", "base participant %d stopped", pid_local);
                stopCount.fetch_add(1);
                std::lock_guard<std::mutex> lock(stopMutex);
                stopCv.notify_all();
            });
        }
    }

    {
        std::unique_lock<std::mutex> lock(stopMutex);
        stopCv.wait_for(lock, std::chrono::seconds(5), [&] {
            return stopCount.load() >= (int)baseStates.size();
        });
    }

    for (auto& s : baseStates) {
        s->instance.reset();
    }

    GoSfu_Destroy(sfuHandle);
    GoSfu_Shutdown();

    // Print summary
    bool success = result.success && !anyFailed && (completedCycles == churnCycles);

    printf("\n=== Group Churn Test Summary ===\n");
    printf("Base participants:      %d (custom=%d, reference=%d)\n",
           baseCount, customParticipants, referenceParticipants);
    printf("Churn cycles:           %d/%d completed\n", completedCycles, churnCycles);
    printf("Video:                  %s\n", video ? "yes" : "no");
    printf("Stabilization:          %ds\n", duration);
    printf("Base connected:         %d/%d\n", result.connectedCount, result.totalParticipants);
    printf("Base audio received:    %d/%d\n", result.audioReceivedCount, result.totalParticipants);
    if (video) {
        printf("Base video received:    %d/%d\n", result.videoReceivedPairs, result.videoExpectedPairs);
    }
    printf("Result:                 %s\n", success ? "SUCCESS" : "FAILED");

    // Clean up log files
    for (const auto& s : baseStates) {
        unlink(s->logPath.c_str());
    }

    fflush(stdout);
    fflush(stderr);
    _exit(success ? 0 : 1);
}
