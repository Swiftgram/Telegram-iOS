load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

sgdeps = [
    "//Swiftgram/SGSimpleSettings:SGSimpleSettings" 
]


swift_library(
    name = "ChatMessageInteractiveFileNode",
    module_name = "ChatMessageInteractiveFileNode",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + [
        "//submodules/AsyncDisplayKit",
        "//submodules/Postbox",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//submodules/TelegramPresentationData",
        "//submodules/AccountContext",
        "//submodules/PhotoResources",
        "//submodules/TelegramStringFormatting",
        "//submodules/SemanticStatusNode",
        "//submodules/FileMediaResourceStatus",
        "//submodules/CheckNode",
        "//submodules/MusicAlbumArtResources",
        "//submodules/AudioBlob",
        "//submodules/ContextUI",
        "//submodules/ChatPresentationInterfaceState",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/AudioTranscriptionButtonComponent",
        "//submodules/TelegramUI/Components/AudioWaveformComponent",
        "//submodules/ShimmerEffect",
        "//submodules/Media/ConvertOpusToAAC",
        "//submodules/Media/LocalAudioTranscription",
        "//submodules/TextSelectionNode",
        "//submodules/TelegramUI/Components/AudioTranscriptionPendingIndicatorComponent",
        "//submodules/UndoUI",
        "//submodules/TelegramNotices",
        "//submodules/TelegramUI/Components/ChatControllerInteraction",
        "//submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode",
        "//submodules/TelegramUI/Components/Chat/ChatHistoryEntry",
        "//submodules/TelegramUI/Components/Chat/ChatMessageItemCommon",
        "//submodules/AnimatedCountLabelNode",
        "//submodules/AudioWaveform",
        "//submodules/DeviceProximity",
    ],
    visibility = [
        "//visibility:public",
    ],
)
