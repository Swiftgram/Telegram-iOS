load(
    "@build_bazel_rules_apple//apple:apple.bzl",
    "apple_dynamic_xcframework_import",
)

# Python 3.11 runtime for the exteraGram-compatible plugin engine.
#
# Fetched by `build-system/setup_python.py`; the binaries are not tracked in
# git. `Python.framework` is a dylib, so it is imported dynamically and copied
# into `Payload/TrollGram.app/Frameworks/` by the release workflow.
apple_dynamic_xcframework_import(
    name = "Python",
    xcframework_imports = glob(["Python.xcframework/**"], allow_empty = True),
    visibility = [
        "//visibility:public",
    ],
)

# Stdlib archive (`lib/python3.11/...`), unzipped on first launch by
# `EmbeddedPython`. Bundled as data so the path stays flat and predictable.
filegroup(
    name = "PythonStdlib",
    srcs = glob(["resources/python.zip"], allow_empty = True),
    visibility = [
        "//visibility:public",
    ],
)
