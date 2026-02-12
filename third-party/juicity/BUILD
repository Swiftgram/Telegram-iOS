load("@build_bazel_rules_apple//apple:apple.bzl", "apple_static_xcframework_import")

# Import the pre-built JuicityBridge.xcframework.
# Build with: cd third-party/juicity && ./build-xcframework.sh
apple_static_xcframework_import(
    name = "JuicityBridge",
    xcframework_imports = glob(["JuicityBridge.xcframework/**"]),
    visibility = ["//visibility:public"],
)
