#!/usr/bin/env python3
"""Re-sign an unsigned TrollGram .ipa with a personal Apple certificate.

Usage:

    python3 build-system/sign_ipa.py \
        --input Payload.ipa --output TrollGram-signed.ipa \
        --p12 cert.p12 --password secret --profile profile.mobileprovision

The script imports the .p12 into a throw-away keychain, rewrites the bundle
identifier when the provisioning profile does not cover the original one, drops
nested code that the profile cannot cover (watchOS app, app extensions) and
signs everything inside-out with the entitlements taken from the profile.

Exit code 0 means the produced IPA passed `codesign --verify --deep --strict`.
"""

import argparse
import datetime
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile


def log(message):
    print("[sign] %s" % message, flush=True)


def run(arguments, **kwargs):
    try:
        return subprocess.run(arguments, check=True, capture_output=True, text=True, **kwargs)
    except subprocess.CalledProcessError as error:
        sys.stderr.write("command failed: %s\n" % " ".join(arguments))
        if error.stdout:
            sys.stderr.write(error.stdout)
        if error.stderr:
            sys.stderr.write(error.stderr)
        raise


def try_run(arguments):
    """Runs a command and returns its stderr (empty when it succeeded).

    The output matters when the command fails: `security import` explains a
    rejected .p12 in exactly one line of stderr, and without it "wrong
    password" is the only thing left to say.
    """
    result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode == 0:
        return ""
    return (result.stderr or result.stdout or "exit status %d" % result.returncode).strip()


def read_profile(path):
    result = subprocess.run(
        ["security", "cms", "-D", "-i", path],
        check=True,
        capture_output=True,
    )
    return plistlib.loads(result.stdout)


def unwrap_base64_p12(p12_path):
    """A secret that was base64-encoded twice decodes to base64 text; decode it once more.

    Returns the path of the usable DER file (the input itself when nothing had to be done).
    """
    with open(p12_path, "rb") as handle:
        data = handle.read()
    log("p12 file: %d bytes, %s" % (len(data), "DER" if data[:1] == b"\x30" else "not DER (first byte 0x%02x)" % (data[:1] or b"\x00")[0]))
    stripped = data.strip()
    if stripped[:1] != b"\x30" and re.fullmatch(rb"[A-Za-z0-9+/=\r\n]+", stripped or b"-"):
        import base64
        try:
            decoded = base64.b64decode(stripped, validate=False)
        except ValueError:
            return p12_path
        if decoded[:1] == b"\x30":
            log("the p12 secret was base64-encoded twice, decoded it once more")
            fixed_path = p12_path + ".der"
            with open(fixed_path, "wb") as handle:
                handle.write(decoded)
            return fixed_path
    return p12_path


def convert_p12_for_macos(p12_path, password, directory):
    """Re-export a .p12 with the older algorithms that macOS `security import` understands.

    OpenSSL 3 writes AES-256/PBKDF2/SHA-256 containers by default, which `security` can
    reject with "Unable to decode the provided data". Returns the new path or None.
    """
    environment = dict(os.environ, SIGN_P12_PASSWORD=password)
    pem_path = os.path.join(directory, "identity.pem")
    converted_path = os.path.join(directory, "identity-compat.p12")
    read = None
    for extra in (["-legacy"], []):
        read = subprocess.run(
            ["openssl", "pkcs12", "-in", p12_path, "-nodes", "-passin", "env:SIGN_P12_PASSWORD", "-out", pem_path] + extra,
            capture_output=True, text=True, env=environment,
        )
        if read.returncode == 0:
            break
    if read is None or read.returncode != 0:
        log("openssl could not read the .p12 either (wrong password or not a PKCS#12 file)")
        return None
    export = subprocess.run(
        [
            "openssl", "pkcs12", "-export", "-in", pem_path, "-out", converted_path,
            "-passout", "env:SIGN_P12_PASSWORD",
            "-certpbe", "PBE-SHA1-3DES", "-keypbe", "PBE-SHA1-3DES", "-macalg", "sha1",
        ],
        capture_output=True, text=True, env=environment,
    )
    os.remove(pem_path)
    if export.returncode != 0:
        log("could not re-export the .p12 in a compatible format")
        return None
    return converted_path


def import_certificate(p12_path, password, keychain):
    keychain_password = "trollgram-sign"
    try_run(["security", "delete-keychain", keychain])
    run(["security", "create-keychain", "-p", keychain_password, keychain])
    run(["security", "set-keychain-settings", "-lut", "21600", keychain])
    run(["security", "unlock-keychain", "-p", keychain_password, keychain])

    def security_import(path):
        return try_run([
            "security", "import", path,
            "-P", password,
            "-A", "-t", "cert", "-f", "pkcs12",
            "-k", keychain,
        ])

    p12_path = unwrap_base64_p12(p12_path)
    error = security_import(p12_path)
    if error:
        log("`security import` rejected the .p12: %s" % error)
        log("retrying with a macOS-compatible re-export")
        converted_path = convert_p12_for_macos(p12_path, password, os.path.dirname(keychain))
        error = None if converted_path is None else security_import(converted_path)
        if converted_path is None or error:
            if error:
                log("the re-exported .p12 was rejected too: %s" % error)
            raise SystemExit(
                "the .p12 could not be imported: %s. Check the P12_BASE64 secret (the base64 of the .p12 file, one "
                "line) and P12_PASSWORD (the password used when exporting the certificate; an empty secret counts "
                "as an empty password)." % (error or "the file is not a PKCS#12 archive")
            )
    run([
        "security", "set-key-partition-list",
        "-S", "apple-tool:,apple:,codesign:",
        "-k", keychain_password, keychain,
    ])
    # Prepend the throw-away keychain to the existing search list. The list
    # contains "login.keychain-db" on modern macOS, so it must be reused
    # instead of hardcoding "login.keychain".
    existing = run(["security", "list-keychains", "-d", "user"]).stdout
    existing_keychains = [line.strip().strip('"') for line in existing.splitlines() if line.strip()]
    run(["security", "list-keychains", "-d", "user", "-s", keychain] + existing_keychains)

    listing = run(["security", "find-identity", "-v", "-p", "codesigning", keychain]).stdout
    # Each line is `  1) <SHA-1 hash> "iPhone Distribution: Name (TEAMID)"`, so the
    # hash sits between the index and the quoted name: matching `) "` alone never
    # matches, which reported a perfectly imported identity as missing.
    match = re.search(r'^\s*\d+\)\s+[0-9A-Fa-f]+\s+"([^"]+)"', listing, re.MULTILINE)
    if match is None:
        sys.stderr.write(listing)
        raise SystemExit(
            "no code signing identity found in the .p12 (wrong password?). "
            "`security find-identity` printed:\n%s" % (listing.strip() or "<nothing>")
        )
    return match.group(1)


def covers(profile_app_id, bundle_id):
    if profile_app_id.endswith("*"):
        return bundle_id.startswith(profile_app_id[:-1])
    return profile_app_id == bundle_id


def write_entitlements(profile_entitlements, team_id, bundle_id, path):
    entitlements = dict(profile_entitlements)
    entitlements["application-identifier"] = "%s.%s" % (team_id, bundle_id)
    entitlements["com.apple.developer.team-identifier"] = team_id
    # Only valid for App Store profiles, codesign rejects it from the outside.
    entitlements.pop("beta-reports-active", None)
    with open(path, "wb") as handle:
        plistlib.dump(entitlements, handle)


def strip_signature(path):
    for name in ("_CodeSignature", "SC_Info"):
        candidate = os.path.join(path, name)
        if os.path.isdir(candidate):
            shutil.rmtree(candidate)
    return path


def sign(path, identity, entitlements_path=None):
    arguments = ["codesign", "--force", "--sign", identity, "--timestamp=none"]
    if entitlements_path is not None:
        arguments += ["--entitlements", entitlements_path]
    arguments.append(path)
    run(arguments)


def bundle_identifier(app_path):
    with open(os.path.join(app_path, "Info.plist"), "rb") as handle:
        return plistlib.load(handle)["CFBundleIdentifier"]


def set_bundle_identifier(app_path, bundle_id):
    plist_path = os.path.join(app_path, "Info.plist")
    with open(plist_path, "rb") as handle:
        info = plistlib.load(handle)
    info["CFBundleIdentifier"] = bundle_id
    with open(plist_path, "wb") as handle:
        plistlib.dump(info, handle)


def nested_bundles(app_path):
    """Every nested code bundle, deepest paths first."""
    found = []
    for directory, dirnames, filenames in os.walk(app_path):
        for name in list(dirnames):
            if name.endswith((".framework", ".appex")):
                found.append(os.path.join(directory, name))
        for name in filenames:
            if name.endswith(".dylib"):
                found.append(os.path.join(directory, name))
    found.sort(key=lambda item: item.count(os.sep), reverse=True)
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--p12", required=True)
    parser.add_argument("--password", default="")
    parser.add_argument("--profile", required=True)
    arguments = parser.parse_args()

    profile = read_profile(arguments.profile)
    entitlements = profile.get("Entitlements", {})
    profile_app_id = entitlements.get("application-identifier")
    if not profile_app_id:
        raise SystemExit("the provisioning profile has no application-identifier")

    team_id = entitlements.get("com.apple.developer.team-identifier") or profile_app_id.split(".", 1)[0]

    expiration = profile.get("ExpirationDate")
    if expiration is not None and expiration < datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise SystemExit("the provisioning profile expired on %s" % expiration)

    devices = profile.get("ProvisionedDevices")
    if devices is not None and not profile.get("ProvisionsAllDevices"):
        log("development profile: the device UDID must be registered in it (%d device(s))" % len(devices))

    with tempfile.TemporaryDirectory() as temporary:
        keychain = os.path.join(temporary, "sign.keychain-db")
        identity = import_certificate(arguments.p12, arguments.password, keychain)
        log("identity: %s" % identity)

        work = os.path.join(temporary, "work")
        os.makedirs(work, exist_ok=True)
        # unzip/zip keep permissions and the framework symlinks intact.
        run(["unzip", "-q", os.path.abspath(arguments.input), "-d", work])

        payload = os.path.join(work, "Payload")
        apps = [name for name in os.listdir(payload) if name.endswith(".app")]
        if len(apps) != 1:
            raise SystemExit("expected exactly one .app in Payload, found %r" % apps)
        app_path = os.path.join(payload, apps[0])
        log("app: %s" % apps[0])

        original_bundle_id = bundle_identifier(app_path)
        bundle_id = original_bundle_id

        if not covers(profile_app_id, bundle_id):
            if profile_app_id.endswith("*"):
                raise SystemExit(
                    "the profile covers %r, which does not include %r" % (profile_app_id, bundle_id)
                )
            bundle_id = profile_app_id.split(".", 1)[1]
            log("profile bundle id %r != app %r, renaming the app" % (bundle_id, original_bundle_id))
            set_bundle_identifier(app_path, bundle_id)

        # The app derives its App Group from the bundle id ("group.<bundle id>"). A profile without that
        # group leaves the shared container unreachable at launch, so say it here instead of in the app.
        expected_group = "group.%s" % bundle_id
        profile_groups = entitlements.get("com.apple.security.application-groups") or []
        if expected_group not in profile_groups:
            log(
                "warning: the profile does not contain the app group %r (it has %r); the app will fall back "
                "to its own sandbox for data. Add the group to the App ID and regenerate the profile for "
                "a shared container." % (expected_group, profile_groups)
            )

        # watchOS code needs watchOS provisioning profiles - never available here.
        watch_path = os.path.join(app_path, "Watch")
        if os.path.isdir(watch_path):
            shutil.rmtree(watch_path)
            log("removed Watch/")

        plugins_path = os.path.join(app_path, "PlugIns")
        if os.path.isdir(plugins_path):
            plugin_ids = []
            for name in os.listdir(plugins_path):
                if name.endswith(".appex"):
                    try:
                        plugin_ids.append(bundle_identifier(os.path.join(plugins_path, name)))
                    except Exception:
                        plugin_ids.append("<unknown>")
            uncovered = [item for item in plugin_ids if not covers(profile_app_id, item)]
            if uncovered:
                shutil.rmtree(plugins_path)
                log("removed PlugIns/ (profile does not cover %s)" % ", ".join(uncovered))
            else:
                log("keeping extensions: %s" % ", ".join(plugin_ids))

        entitlements_dir = os.path.join(temporary, "entitlements")
        os.makedirs(entitlements_dir, exist_ok=True)

        def prepare(target_path, target_bundle_id, embedded_profile=None):
            """Strip, add the profile and write the entitlements for a bundle."""
            strip_signature(target_path)
            if embedded_profile is not None:
                shutil.copyfile(embedded_profile, os.path.join(target_path, "embedded.mobileprovision"))
            plist_path = os.path.join(
                entitlements_dir, target_bundle_id.replace("/", "_") + ".plist"
            )
            write_entitlements(entitlements, team_id, target_bundle_id, plist_path)
            return plist_path

        for nested in nested_bundles(app_path):
            if nested.endswith(".appex"):
                nested_id = bundle_identifier(nested)
                plist_path = prepare(nested, nested_id, arguments.profile)
                sign(nested, identity, plist_path)
                log("signed extension %s" % nested_id)
            elif nested.endswith(".framework"):
                strip_signature(nested)
                sign(nested, identity)
                log("signed framework %s" % os.path.basename(nested))
            else:
                sign(nested, identity)

        plist_path = prepare(app_path, bundle_id, arguments.profile)
        sign(app_path, identity, plist_path)

        run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", app_path])

        if os.path.exists(arguments.output):
            os.remove(arguments.output)
        run(["zip", "-qry", os.path.abspath(arguments.output), "Payload"], cwd=work)

    size = os.path.getsize(arguments.output) / (1024.0 * 1024.0)
    log("signed %s -> %s (%.1f MB)" % (bundle_id, arguments.output, size))


if __name__ == "__main__":
    main()
