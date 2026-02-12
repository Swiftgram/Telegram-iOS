load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "JuicityClient",
    module_name = "JuicityClient",
    srcs = glob(["Sources/**/*.swift"]),
    visibility = ["//visibility:public"],
    deps = [
        # Uncomment when JuicityBridge.xcframework is built:
        # "//third-party/juicity:JuicityBridge",
    ],
)
