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
        "//Swiftgram/SGLogging:SGLogging",
        "//Swiftgram/SGWebAppExtensions:SGWebAppExtensions",
        "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
        "//Swiftgram/SGWebSettingsScheme:SGWebSettingsScheme",
        "//Swiftgram/SGRegDateScheme:SGRegDateScheme",
        "//Swiftgram/SGRequests:SGRequests",
        "//Swiftgram/SGConfig:SGConfig"
    ],
    visibility = [
        "//visibility:public",
    ],
)
