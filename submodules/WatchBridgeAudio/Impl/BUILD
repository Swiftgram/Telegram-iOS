load("@rules_cc//cc:objc_library.bzl", "objc_library")

objc_library(
    name = "WatchBridgeAudioImpl",
    enable_modules = True,
    module_name = "WatchBridgeAudioImpl",
    srcs = glob([
        "Sources/**/*.m",
        "Sources/**/*.mm",
        "Sources/**/*.h",
    ], allow_empty=True),
    hdrs = glob([
        "PublicHeaders/**/*.h",
    ]),
    includes = [
        "PublicHeaders",
    ],
    deps = [
        "//submodules/SSignalKit/SSignalKit:SSignalKit",
        "//submodules/OpusBinding:OpusBinding",
    ],
    sdk_frameworks = [
        "Foundation",
    ],
    visibility = [
        "//visibility:public",
    ],
)
