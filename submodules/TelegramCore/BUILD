load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

sgdeps = [
    "//Swiftgram/SwiftSoup:SwiftSoup",
    "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
    "//Swiftgram/SGTranslationLangFix:SGTranslationLangFix",
    "//Swiftgram/SGWebSettingsScheme:SGWebSettingsScheme",
    "//Swiftgram/SGConfig:SGConfig",
    "//Swiftgram/SGLogging:SGLogging",
]

sgsrc = [
    "//Swiftgram/SGIQTP:SGIQTP",
]

swift_library(
    name = "TelegramCore",
    module_name = "TelegramCore",
    srcs = sgsrc + glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + [
        "//submodules/TelegramApi:TelegramApi",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/CloudData:CloudData",
        "//submodules/EncryptionProvider:EncryptionProvider",
        "//submodules/CryptoUtils:CryptoUtils",
        "//submodules/NetworkLogging:NetworkLogging",
        "//submodules/Reachability:Reachability",
        "//submodules/ManagedFile:ManagedFile",
        "//submodules/Utils/RangeSet:RangeSet",
        "//submodules/Utils/DarwinDirStat",
        "//submodules/Emoji",
    ],
    visibility = [
        "//visibility:public",
    ],
)
