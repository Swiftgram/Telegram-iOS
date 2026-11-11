#!/usr/bin/env python3
"""Check the Eblogram payload layout without printing credentials or identifiers."""

import argparse
import plistlib
import zipfile
from pathlib import PurePosixPath


def check_ipa(ipa, variant):
    def require(condition, message):
        if not condition:
            raise SystemExit(message)

    with zipfile.ZipFile(ipa) as archive:
        members = set(archive.namelist())
        app_plists = [
            path for path in members
            if PurePosixPath(path).match("Payload/*.app/Info.plist")
            and len(PurePosixPath(path).parts) == 3
        ]
        require(len(app_plists) == 1, "Expected exactly one top-level application.")
        plist_path = app_plists[0]
        info = plistlib.loads(archive.read(plist_path))
        prefix = plist_path.removesuffix("Info.plist")
        payload_paths = {path.removeprefix(prefix) for path in members if path.startswith(prefix)}
        require(info.get("CFBundleDisplayName") == "Eblogram", "Display name is incorrect.")
        require(info.get("CFBundleName") == "Eblogram", "Bundle name is incorrect.")
        require(info.get("EblogramStandalone") is (variant == "standalone"), "Build variant flag is incorrect.")
        require(info.get("CFBundleExecutable") in payload_paths, "Main executable is missing.")
        require("arm64" in info.get("UIRequiredDeviceCapabilities", []), "arm64 device capability is missing.")
        require(
            any(PurePosixPath(path).name == "LaunchScreen.nib" or "LaunchScreen.nib/" in path
                or "LaunchScreen.storyboardc/" in path for path in payload_paths),
            "Compiled launch storyboard is missing.",
        )
        require(
            "en.lproj/Localizable.strings" in payload_paths,
            "The English launch-time strings are missing.",
        )
        scenes = info.get("UIApplicationSceneManifest", {}).get("UISceneConfigurations", {})
        require(
            any(scene.get("UISceneDelegateClassName") == "SceneDelegate"
                for scene in scenes.get("UIWindowSceneSessionRoleApplication", [])),
            "Application scene delegate is missing.",
        )
        schemes = {
            scheme for url_type in info.get("CFBundleURLTypes", [])
            for scheme in url_type.get("CFBundleURLSchemes", [])
        }
        require({"eblogram", "tg", "sg"} <= schemes, "A URL scheme is missing.")
        for framework in ("MtProtoKit", "SwiftSignalKit", "Postbox", "TelegramCore", "TelegramUI"):
            require(
                f"Frameworks/{framework}Framework.framework/{framework}Framework" in payload_paths,
                f"The {framework} framework executable is missing.",
            )

        extensions = {
            path.split("/")[1] for path in payload_paths
            if path.startswith("PlugIns/") and path.endswith(".appex/Info.plist")
        }
        if variant == "standalone":
            require(not any(path.startswith(("PlugIns/", "Watch/")) for path in payload_paths),
                    "Standalone payload contains an extension or watch app.")
        else:
            require(len(extensions) == 6, "Full payload does not contain the six expected iOS extensions.")

    print(f"Eblogram {variant} IPA layout OK.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa")
    parser.add_argument("--variant", choices=("standalone", "full"), required=True)
    args = parser.parse_args()
    check_ipa(args.ipa, args.variant)
