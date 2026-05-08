load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

sgsrc = [
    "//Swiftgram/SGSwiftSignalKit:SGSwiftSignalKit"
]

swift_library(
    name = "SwiftSignalKit",
    module_name = "SwiftSignalKit",
    srcs = sgsrc + glob([
        "Source/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    visibility = [
        "//visibility:public",
    ],
)
