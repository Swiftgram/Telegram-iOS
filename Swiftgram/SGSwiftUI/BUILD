load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SGSwiftUI",
    module_name = "SGSwiftUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        # "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/TelegramPresentationData:TelegramPresentationData"
    ],
    visibility = [
        "//visibility:public",
    ],
)
