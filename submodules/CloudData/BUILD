load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_configuration//:variables.bzl", "telegram_enable_icloud")

swift_library(
    name = "CloudData",
    module_name = "CloudData",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    # CKContainer throws an Objective-C exception (an abort at launch) when the app has no iCloud
    # entitlements, so CloudKit is only touched when the build configuration enables iCloud.
    defines = ["TELEGRAM_ENABLE_ICLOUD"] if telegram_enable_icloud else [],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/EncryptionProvider:EncryptionProvider",
    ],
    visibility = [
        "//visibility:public",
    ],
)
