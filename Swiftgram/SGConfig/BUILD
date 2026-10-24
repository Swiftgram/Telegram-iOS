load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SGConfig",
    module_name = "SGConfig",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/BuildConfig:BuildConfig"
    ],
    visibility = [
        "//visibility:public",
    ],
)