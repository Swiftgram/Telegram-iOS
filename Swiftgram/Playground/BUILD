load("@bazel_skylib//rules:common_settings.bzl",
    "bool_flag",
)
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load(
    "@rules_xcodeproj//xcodeproj:defs.bzl",
    "top_level_targets",
    "xcodeproj",
)
load(
    "@build_configuration//:variables.bzl", "telegram_bazel_path"
)

bool_flag(
    name = "disableProvisioningProfiles",
    build_setting_default = False,
    visibility = ["//visibility:public"],
)

config_setting(
    name = "disableProvisioningProfilesSetting",
    flag_values = {
        ":disableProvisioningProfiles": "True",
    },
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
        "//Swiftgram/SGSwiftUI:SGSwiftUI",
    ],
    data = [
        "//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data",
    ],
    visibility = ["//visibility:public"],
)

ios_application(
    name = "Playground",
    bundle_id = "app.swiftgram.ios.Playground",
    families = [
        "iphone",
        "ipad",
    ],
    provisioning_profile = select({
        ":disableProvisioningProfilesSetting": None,
        "//conditions:default": "codesigning/Playground.mobileprovision",
    }),
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
    top_level_targets = top_level_targets(
        labels = [
            ":Playground",
        ],
        target_environments = ["device", "simulator"],
    ),
)