load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SGAPIToken",
    module_name = "SGAPIToken",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
        "//Swiftgram/SGLogging:SGLogging",
        "//Swiftgram/SGWebSettingsScheme:SGWebSettingsScheme",
        "//Swiftgram/SGConfig:SGConfig",
        "//Swiftgram/SGWebAppExtensions:SGWebAppExtensions",
    ],
    visibility = [
        "//visibility:public",
    ],
)
