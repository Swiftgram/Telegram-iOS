load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# exteraGram-compatible plugin host.
#
# The Python runtime is optional: without //third-party/python/Python.xcframework
# the module still compiles and runs in stub mode (`EmbeddedPython` returns
# false from `isAvailable`).
swift_library(
    name = "PythonPlugins",
    module_name = "PythonPlugins",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//third-party/ZipArchive:ZipArchive",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Python plugin SDK emulation (base_plugin, ui.settings, client_utils, ...).
filegroup(
    name = "PythonStdlib",
    srcs = glob(["stdlib/**/*.py"]),
    visibility = ["//visibility:public"],
)
