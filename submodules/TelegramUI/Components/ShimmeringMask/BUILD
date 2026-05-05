load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ShimmeringMask",
    module_name = "ShimmeringMask",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/ShimmerEffect",
        "//submodules/ComponentFlow",
    ],
    visibility = [
        "//visibility:public",
    ],
)
