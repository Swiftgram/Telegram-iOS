load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

sgdeps = [
    "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
    "//submodules/TextFormat:TextFormat"
]

swift_library(
    name = "TranslateUI",
    module_name = "TranslateUI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/AccountContext:AccountContext",
        "//submodules/AlertUI:AlertUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/Speak:Speak",
        "//submodules/ManagedAnimationNode:ManagedAnimationNode",
        "//submodules/TelegramStringFormatting:TelegramStringFormatting",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",        
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/Components/ViewControllerComponent:ViewControllerComponent",
        "//submodules/Components/MultilineTextComponent:MultilineTextComponent",
        "//submodules/Components/MultilineTextWithEntitiesComponent:MultilineTextWithEntitiesComponent",
        "//submodules/Components/BundleIconComponent:BundleIconComponent",
        "//submodules/UndoUI:UndoUI",
        "//submodules/ActivityIndicator:ActivityIndicator",
        "//submodules/ChatListSearchItemNode:ChatListSearchItemNode",
        "//submodules/ShimmerEffect:ShimmerEffect",
    ],
    visibility = [
        "//visibility:public",
    ],
)
