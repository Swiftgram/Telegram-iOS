load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatMessageRichDataBubbleContentNode",
    module_name = "ChatMessageRichDataBubbleContentNode",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AccountContext",
        "//submodules/InstantPageUI",
        "//submodules/TelegramUI/Components/Chat/ChatMessageBubbleContentNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageItemCommon",
        "//submodules/TelegramUI/Components/ChatControllerInteraction",
        "//submodules/TelegramUI/Components/TextLoadingEffect",
        "//submodules/TelegramUIPreferences",
        "//submodules/TextSelectionNode",
        "//submodules/TelegramUI/Components/ShimmeringMask:ShimmeringMask",
        "//submodules/TelegramUI/Components/InteractiveTextComponent:InteractiveTextComponent",
        "//submodules/TelegramUI/Components/StreamingTextReveal:StreamingTextReveal",
        "//submodules/TelegramUI/Components/TextNodeWithEntities:TextNodeWithEntities",
    ],
    visibility = [
        "//visibility:public",
    ],
)
