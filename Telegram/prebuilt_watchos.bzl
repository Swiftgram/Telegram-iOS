"""Embeds the standalone, xcodebuild-built tgwatch watch app into the Bazel iOS build.

`apple_prebuilt_watchos_application` runs `xcodebuild` (via prebuilt_watchos_build.sh)
against an exported tgwatch source tree, optionally codesigns the result, and exposes
it through the providers that `ios_application(watch_application = ...)` consumes:

  * AppleBundleInfo      — bundle metadata (the host reads only `.product_type`).
  * AppleEmbeddableInfo  — `watch_bundles` (the zipped .app placed under Watch/).

The watch source tree lives at an external, machine-specific absolute path passed via
`--define=watchAppSourcePath=...`; the build action is therefore local/uncached.

Notes on the rules_apple providers used here:
  * AppleBundleInfo's public init is banned; we build it with the internal raw
    initializer `new_applebundleinfo` (rules_apple is vendored + pinned in this repo,
    so depending on the internal label is safe).
"""

load(
    "@build_bazel_rules_apple//apple/internal:providers.bzl",
    "new_applebundleinfo",
    "new_watchosapplicationbundleinfo",
)
load("@build_bazel_rules_apple//apple/internal/providers:embeddable_info.bzl", "AppleEmbeddableInfo")

def _apple_prebuilt_watchos_application_impl(ctx):
    source_path = ctx.var.get("watchAppSourcePath", "")
    if not source_path:
        fail("apple_prebuilt_watchos_application requires --define=watchAppSourcePath=<abs path to exported tgwatch sources>")
    api_id = ctx.var.get("watchApiId", "0")
    api_hash = ctx.var.get("watchApiHash", "placeholder")
    identity = ctx.var.get("watchSigningIdentity", "")

    # The provisioning profile is an external, machine-specific absolute path
    # (like watchAppSourcePath), passed via --define rather than a Bazel label so
    # the gitignored profile need not be exposed as a target. The local action
    # reads it directly. Empty => unsigned build.
    profile = ctx.var.get("watchProvisioningProfile", "")
    # The embedded watch app's CFBundleShortVersionString / CFBundleVersion must match
    # the host app, or rules_apple's child-version verification fails. Source the
    # marketing version from versions.json (same as the host's VersionInfoPlist) and the
    # build version from buildNumber (Make.py always emits --define=buildNumber).
    build_number = ctx.var.get("buildNumber", "1")
    archive = ctx.actions.declare_file(ctx.label.name + ".zip")
    # The host ios_application reads the watch app's Info.plist (via AppleBundleInfo.infoplist)
    # to verify WKCompanionAppBundleIdentifier against the host bundle id, so expose it as a
    # separate output (resources.bzl bundle_verification crashes on a None infoplist).
    infoplist = ctx.actions.declare_file(ctx.label.name + "_Info.plist")

    ctx.actions.run(
        executable = "/bin/bash",
        arguments = [
            ctx.file._worker.path,
            source_path,
            archive.path,
            api_id,
            api_hash,
            identity,
            profile,
            infoplist.path,
            ctx.file.versions_json.path,
            build_number,
        ],
        inputs = [ctx.file._worker, ctx.file.versions_json],
        outputs = [archive, infoplist],
        mnemonic = "PrebuiltWatchosBuild",
        progress_message = "Building%s watch app via xcodebuild" % (" + signing" if identity else ""),
        # The watch source tree is an external absolute path, not a tracked input,
        # so the action cannot be cached or sandboxed and may fetch SwiftPM deps.
        execution_requirements = {
            "no-cache": "1",
            "no-sandbox": "1",
            "no-remote": "1",
            "local": "1",
            "requires-network": "1",
        },
        use_default_shell_env = True,
    )

    return [
        DefaultInfo(files = depset([archive])),
        new_applebundleinfo(
            archive = archive,
            bundle_id = ctx.attr.bundle_id,
            bundle_name = ctx.attr.bundle_name,
            bundle_extension = ".app",
            platform_type = "watchos",
            # Must be a single-target watchOS app (NOT watch2_application) so the host
            # skips the watchos_stub partial (see ios_rules.bzl product_type check).
            product_type = "com.apple.product-type.application",
            minimum_os_version = ctx.attr.minimum_os_version,
            minimum_deployment_os_version = ctx.attr.minimum_os_version,
            infoplist = infoplist,
            binary = None,
            entitlements = None,
            # Best-effort constant; the host ios_application reads only product_type.
            uses_swift = True,
            extension_safe = False,
        ),
        # Marker provider required by ios_application's watch_application attr
        # (providers = [[AppleBundleInfo, WatchosApplicationBundleInfo]]).
        new_watchosapplicationbundleinfo(),
        AppleEmbeddableInfo(
            # The signed (or unsigned) .app archive, expanded into the host's Watch/ section.
            watch_bundles = depset([archive]),
            # Empty: the worker signs everything inside the watch app itself.
            signed_frameworks = depset(),
        ),
    ]

apple_prebuilt_watchos_application = rule(
    implementation = _apple_prebuilt_watchos_application_impl,
    attrs = {
        "bundle_id": attr.string(default = "ph.telegra.Telegraph.watchkitapp"),
        "bundle_name": attr.string(default = "tgwatch Watch App"),
        "minimum_os_version": attr.string(default = "26.0"),
        "versions_json": attr.label(
            allow_single_file = True,
            default = "//:versions.json",
            doc = "Source of the marketing version (key 'app'), kept in sync with the host app.",
        ),
        "_worker": attr.label(
            default = "//Telegram:prebuilt_watchos_build.sh",
            allow_single_file = True,
        ),
    },
)
