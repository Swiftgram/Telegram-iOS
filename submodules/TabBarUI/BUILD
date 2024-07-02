load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

sgdeps = [
    "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
]

sgsrc = [
    "//Swiftgram/SGTabBarHeightModifier:SGTabBarHeightModifier"
]

swift_library(
    name = "TabBarUI",
    module_name = "TabBarUI",
    srcs = sgsrc + glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
    	"//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AnimatedStickerNode",
        "//submodules/TelegramAnimatedStickerNode",
        "//submodules/TelegramPresentationData",
        "//submodules/ComponentFlow",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/TelegramUI/Components/TabBarComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
