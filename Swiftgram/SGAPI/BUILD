load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SGAPI",
    module_name = "SGAPI",
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
        "//Swiftgram/SGWebAppExtensions:SGWebAppExtensions",
        "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
        "//Swiftgram/SGWebSettingsScheme:SGWebSettingsScheme",
        "//Swiftgram/SGRequests:SGRequests",
        "//Swiftgram/SGConfig:SGConfig"
    ],
    visibility = [
        "//visibility:public",
    ],
)
