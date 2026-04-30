#pragma once

#include "api/video/i420_buffer.h"
#include "media/base/adapted_video_track_source.h"
#include "rtc_base/ref_counted_object.h"

#include <atomic>
#include <thread>

// Generates 640x360 I420 frames at 30fps with per-participant color tint
// and an incrementing frame counter rendered as block digits.
class FakeVideoTrackSource : public rtc::AdaptedVideoTrackSource {
public:
    static rtc::scoped_refptr<FakeVideoTrackSource> Create(int participantId);

    ~FakeVideoTrackSource() override;

    void Stop();

    // VideoTrackSourceInterface
    SourceState state() const override { return kLive; }
    bool remote() const override { return false; }
    bool is_screencast() const override { return false; }
    absl::optional<bool> needs_denoising() const override { return false; }

protected:
    explicit FakeVideoTrackSource(int participantId);

private:
    void GenerateThread();
    void RenderDigits(uint8_t* yPlane, int strideY, int frameNumber);

    int participantId_;
    uint8_t uTint_;
    uint8_t vTint_;
    std::atomic<bool> running_{true};
    std::thread thread_;
};
