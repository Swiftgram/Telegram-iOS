load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: Swiftgram
sgdeps = [
    "//Swiftgram/SGInputToolbar:SGInputToolbar",
]
#

swift_library(
    name = "TextFieldComponent",
    module_name = "TextFieldComponent",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + [
        "//submodules/Display",
        "//submodules/ComponentFlow",
        "//submodules/TextFormat",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramPresentationData",
        "//submodules/AccountContext",
        "//submodules/InvisibleInkDustNode",
        "//submodules/TelegramUI/Components/EmojiTextAttachmentView",
        "//submodules/Pasteboard",
        "//submodules/ImageTransparency",
        "//submodules/TelegramUI/Components/Chat/ChatInputTextNode",
        "//submodules/TextInputMenu",
        "//submodules/ObjCRuntimeUtils",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/Speak",
    ],
    visibility = [
        "//visibility:public",
    ],
)
