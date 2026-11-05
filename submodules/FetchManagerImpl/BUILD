load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: Swiftgram
sgdeps = [
    "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
]
#

swift_library(
    name = "FetchManagerImpl",
    module_name = "FetchManagerImpl",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + [ # MARK: Swiftgram
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/AccountContext:AccountContext",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//submodules/Utils/RangeSet:RangeSet",
    ],
    visibility = [
        "//visibility:public",
    ],
)
