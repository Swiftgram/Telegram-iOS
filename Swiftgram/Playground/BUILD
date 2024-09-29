load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load(
    "@rules_xcodeproj//xcodeproj:defs.bzl",
    "top_level_target",
    "xcodeproj",
)
load(
    "@build_configuration//:variables.bzl", "telegram_bazel_path"
)

objc_library(
    name = "PlaygroundMain",
    srcs = [
        "Sources/main.m"
    ],
)


swift_library(
    name = "PlaygroundLib",
    srcs = glob(["Sources/**/*.swift"]),
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/LegacyUI:LegacyUI",
        "//submodules/LegacyComponents:LegacyComponents",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
    ],
    data = [
        "//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data",
    ],
    visibility = ["//visibility:public"],
)

ios_application(
    name = "Playground",
    bundle_id = "app.swiftgram.playground",
    families = [
        "iphone",
        "ipad",
    ],
    infoplists = ["Resources/Info.plist"],
    minimum_os_version = "14.0",
    visibility = ["//visibility:public"],
    strings = [
        "//Telegram:AppStringResources",
    ],
    launch_storyboard = "Resources/LaunchScreen.storyboard",
    deps = [":PlaygroundMain", ":PlaygroundLib"],
)

xcodeproj(
    bazel_path = telegram_bazel_path,
    name = "Playground_xcodeproj",
    build_mode = "bazel",
    project_name = "Playground",
    tags = ["manual"],
    top_level_targets = [
        ":Playground",
    ],
)