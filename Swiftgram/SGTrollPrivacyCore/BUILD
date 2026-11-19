load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# TelegramCore-side glue for TrollGram privacy gates.
swift_library(
    name = "SGTrollPrivacyCore",
    module_name = "SGTrollPrivacyCore",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Swiftgram/SGTrollPrivacy:SGTrollPrivacy",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
