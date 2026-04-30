cc_binary(
    name = "tgcalls_cli",
    srcs = [
        "main.cpp",
        "group_mode.cpp",
        "group_mode.h",
        "group_participant.cpp",
        "group_participant.h",
        "group_churn_mode.cpp",
        "group_churn_mode.h",
        "fake_video_source.h",
        "fake_video_source.cpp",
        "fake_video_sink.h",
    ],
    copts = [
        "-I{}/tgcalls/tgcalls".format("submodules/TgVoipWebrtc"),
        "-Ithird-party/webrtc/webrtc",
        "-Ithird-party/webrtc/dependencies",
        "-Ithird-party/webrtc/absl",
        "-Ithird-party/libyuv",
        "-DRTC_ENABLE_VP9",
        "-DNDEBUG",
        "-std=c++17",
        "-w",
    ] + select({
        "@platforms//os:linux": ["-DWEBRTC_LINUX", "-DWEBRTC_POSIX"],
        "//conditions:default": ["-DWEBRTC_MAC", "-DWEBRTC_POSIX"],
    }),
    linkopts = select({
        "@platforms//os:linux": ["-lpthread", "-lm", "-ldl"],
        "//conditions:default": ["-framework", "CoreFoundation", "-framework", "Security"],
    }),
    deps = [
        "//submodules/TgVoipWebrtc:tgcalls_core",
        "//tools/go_sfu",
    ],
)
