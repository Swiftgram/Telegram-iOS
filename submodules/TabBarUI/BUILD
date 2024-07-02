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
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
    	"//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AnimatedStickerNode:AnimatedStickerNode",
        "//submodules/TelegramAnimatedStickerNode:TelegramAnimatedStickerNode",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
    ],
    visibility = [
        "//visibility:public",
    ],
)
