load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SGGTranslate",
    module_name = "SGGTranslate",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//Swiftgram/SwiftSoup:SwiftSoup",
    ],
    visibility = [
        "//visibility:public",
    ],
)
