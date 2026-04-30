#include "fake_video_source.h"

#include "api/video/video_frame.h"
#include "api/video/video_rotation.h"
#include "rtc_base/time_utils.h"

#include <cstring>

namespace {

constexpr int kWidth = 1280;
constexpr int kHeight = 720;
constexpr int kFps = 30;
constexpr uint8_t kBgY = 80;    // dark background
constexpr uint8_t kDigitY = 235; // white digits
constexpr int kDigitW = 5;
constexpr int kDigitH = 7;
constexpr int kScale = 4;
constexpr int kDigitSpacing = 2; // pixels between digits (scaled)
constexpr int kMargin = 8;       // top-left margin in pixels

// 5x7 bitmap font for digits 0-9. Each entry is 7 rows of 5-bit patterns.
// MSB = leftmost pixel.
static const uint8_t kDigitBitmaps[10][7] = {
    // 0
    {0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110},
    // 1
    {0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110},
    // 2
    {0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111},
    // 3
    {0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110},
    // 4
    {0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010},
    // 5
    {0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110},
    // 6
    {0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110},
    // 7
    {0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000},
    // 8
    {0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110},
    // 9
    {0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100},
};

// 6 color tints cycling: red, green, blue, yellow, cyan, magenta
// UV values for each tint (in I420, U=Cb, V=Cr; neutral=128)
struct UVTint { uint8_t u; uint8_t v; };
static const UVTint kTints[6] = {
    {90,  240},  // red
    {54,  34},   // green
    {240, 110},  // blue
    {16,  146},  // yellow
    {166, 16},   // cyan
    {166, 240},  // magenta
};

} // namespace

FakeVideoTrackSource::FakeVideoTrackSource(int participantId)
    : participantId_(participantId) {
    const auto& tint = kTints[participantId % 6];
    uTint_ = tint.u;
    vTint_ = tint.v;
    thread_ = std::thread(&FakeVideoTrackSource::GenerateThread, this);
}

FakeVideoTrackSource::~FakeVideoTrackSource() {
    Stop();
}

rtc::scoped_refptr<FakeVideoTrackSource> FakeVideoTrackSource::Create(int participantId) {
    return rtc::scoped_refptr<FakeVideoTrackSource>(
        new rtc::RefCountedObject<FakeVideoTrackSource>(participantId));
}

void FakeVideoTrackSource::Stop() {
    if (running_.exchange(false)) {
        if (thread_.joinable()) {
            thread_.join();
        }
    }
}

void FakeVideoTrackSource::GenerateThread() {
    int frameNumber = 0;
    while (running_.load(std::memory_order_relaxed)) {
        auto buffer = webrtc::I420Buffer::Create(kWidth, kHeight);

        // Fill Y plane with dark background
        memset(buffer->MutableDataY(), kBgY, buffer->StrideY() * kHeight);

        // Fill U plane with tint
        int uvHeight = (kHeight + 1) / 2;
        memset(buffer->MutableDataU(), uTint_, buffer->StrideU() * uvHeight);

        // Fill V plane with tint
        memset(buffer->MutableDataV(), vTint_, buffer->StrideV() * uvHeight);

        // Render frame counter digits
        RenderDigits(buffer->MutableDataY(), buffer->StrideY(), frameNumber);

        auto frame = webrtc::VideoFrame::Builder()
            .set_video_frame_buffer(buffer)
            .set_rotation(webrtc::kVideoRotation_0)
            .set_timestamp_us(rtc::TimeMicros())
            .build();

        OnFrame(frame);

        ++frameNumber;
        std::this_thread::sleep_for(std::chrono::milliseconds(1000 / kFps));
    }
}

void FakeVideoTrackSource::RenderDigits(uint8_t* yPlane, int strideY, int frameNumber) {
    // Convert frame number to decimal digits
    char numStr[16];
    snprintf(numStr, sizeof(numStr), "%d", frameNumber);
    int numDigits = static_cast<int>(strlen(numStr));

    int xOffset = kMargin;
    for (int d = 0; d < numDigits; ++d) {
        int digit = numStr[d] - '0';
        const uint8_t* bitmap = kDigitBitmaps[digit];

        for (int row = 0; row < kDigitH; ++row) {
            uint8_t rowBits = bitmap[row];
            for (int col = 0; col < kDigitW; ++col) {
                if (rowBits & (1 << (kDigitW - 1 - col))) {
                    // Fill scaled pixel block
                    int px = xOffset + col * kScale;
                    int py = kMargin + row * kScale;
                    for (int sy = 0; sy < kScale; ++sy) {
                        for (int sx = 0; sx < kScale; ++sx) {
                            int x = px + sx;
                            int y = py + sy;
                            if (x < kWidth && y < kHeight) {
                                yPlane[y * strideY + x] = kDigitY;
                            }
                        }
                    }
                }
            }
        }
        xOffset += kDigitW * kScale + kDigitSpacing;
    }
}
