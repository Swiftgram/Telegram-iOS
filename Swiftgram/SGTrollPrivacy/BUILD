load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Dependency-free privacy settings (pod-style: only Foundation).
# TelegramCore gates are mirrored by //Swiftgram/SGTrollPrivacyCore.
swift_library(
    name = "SGTrollPrivacy",
    module_name = "SGTrollPrivacy",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [],
    visibility = [
        "//visibility:public",
    ],
)
