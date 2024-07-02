load("@build_bazel_rules_apple//apple:resources.bzl", "apple_bundle_import")

apple_bundle_import(
    name = "SGSettingsBundle",
    bundle_imports = glob([
        "Settings.bundle/*",
        "Settings.bundle/**/*",
    ]),
    visibility = ["//visibility:public"]
)