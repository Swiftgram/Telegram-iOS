#pragma once
#include "api/video/video_frame.h"
#include "api/video/video_sink_interface.h"
#include <atomic>

class FakeVideoSink : public rtc::VideoSinkInterface<webrtc::VideoFrame> {
public:
    void OnFrame(const webrtc::VideoFrame& frame) override {
        frameCount_.fetch_add(1, std::memory_order_relaxed);
        int w = frame.width();
        int h = frame.height();
        lastWidth_.store(w, std::memory_order_relaxed);
        lastHeight_.store(h, std::memory_order_relaxed);
    }
    int lastWidth() const { return lastWidth_.load(std::memory_order_relaxed); }
    int lastHeight() const { return lastHeight_.load(std::memory_order_relaxed); }
    int frameCount() const {
        return frameCount_.load(std::memory_order_relaxed);
    }
private:
    std::atomic<int> frameCount_{0};
    std::atomic<int> lastWidth_{0};
    std::atomic<int> lastHeight_{0};
};
