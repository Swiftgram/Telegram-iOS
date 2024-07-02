load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SGStrings",
    module_name = "SGStrings",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AppBundle:AppBundle",
        "//Swiftgram/SGLogging:SGLogging"
    ],
    visibility = [
        "//visibility:public",
    ],
)

filegroup(
    name = "SGLocalizableStrings",
    srcs = glob(["Strings/*.lproj/SGLocalizable.strings"]),
    visibility = [
        "//visibility:public",
    ],
)
