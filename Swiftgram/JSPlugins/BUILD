load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# TrollGram JavaScript plugin host. Uses the JavaScriptCore framework that ships with iOS (linked by the
# `import JavaScriptCore` in the sources; swift_library has no sdk_frameworks), so there is no embedded interpreter
# and no native bridge to build.
swift_library(
    name = "JSPlugins",
    module_name = "JSPlugins",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
