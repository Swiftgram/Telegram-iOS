load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: Swiftgram
sgsrcs = [
    "//Swiftgram/SGSaveToCameraRollExtensions:SGSaveToCameraRollExtensions",
]

sgdeps = [
    "//Swiftgram/SGSimpleSettings:SGSimpleSettings"
]
#

swift_library(
    name = "SaveToCameraRoll",
    module_name = "SaveToCameraRoll",
    srcs = sgsrcs + glob([ # MARK: Swiftgram
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + [ # MARK: Swiftgram
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Display:Display",
        "//submodules/AccountContext:AccountContext",
        "//submodules/DeviceAccess:DeviceAccess",
        "//submodules/LegacyComponents:LegacyComponents",
    ],
    visibility = [
        "//visibility:public",
    ],
)
