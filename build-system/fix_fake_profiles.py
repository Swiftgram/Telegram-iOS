"""Re-signs the bundled fake provisioning profiles with the fake certificate.

The profiles under ``build-system/fake-codesigning/profiles`` expired on
2026-10-30, and both rules_apple's ``plisttool`` and Make.py's
``DirectoryCodesigningSource`` reject expired profiles, which broke every CI
build.

Simply patching the ``ExpirationDate`` bytes is not enough: the profile is a
CMS envelope, so editing the payload invalidates the message digest and
``openssl smime -verify -noverify`` (used by Make.py) fails with
"digest failure". This script re-creates the CMS signature with the bundled
fake certificate instead.

With ``--bundle-id`` the profiles are also retargeted to another bundle id
(application identifiers, app groups and names) and written, together with the
fake certificate, to a new ``--out`` directory laid out like
``build-system/fake-codesigning``. Make.py only picks up a profile whose
application identifier starts with ``<team id>.<bundle id>`` from
appstore-configuration.json, and rules_apple refuses to build a device
configuration without a profile, so the fake profiles must follow the
configured bundle id.

Usage:
    python3 build-system/fix_fake_profiles.py [--year 2036] [--check]
    python3 build-system/fix_fake_profiles.py --bundle-id com.example.App --out DIR

Requires ``openssl`` on PATH.
"""

import argparse
import glob
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAKE_DIR = os.path.join(ROOT, "build-system", "fake-codesigning")
PROFILES = os.path.join(FAKE_DIR, "profiles")
P12_PATH = os.path.join(FAKE_DIR, "certs", "SelfSigned.p12")
P12_PASSWORD = ""  # fake-codesigning uses an empty password
OPENSSL = os.environ.get("OPENSSL") or shutil.which("openssl") or "openssl"


def run(arguments, **kwargs):
    result = subprocess.run(arguments, capture_output=True, **kwargs)
    if result.returncode != 0:
        sys.stderr.write(
            "command failed (%d): %s\n%s\n"
            % (
                result.returncode,
                " ".join(arguments),
                result.stderr.decode("utf-8", "replace"),
            )
        )
        raise SystemExit(1)
    return result


def extract_certificate(directory):
    combined = os.path.join(directory, "combined.pem")
    arguments = [
        OPENSSL, "pkcs12",
        "-in", P12_PATH,
        "-passin", "pass:" + P12_PASSWORD,
        "-nodes",
        "-out", combined,
    ]
    result = subprocess.run(arguments, capture_output=True)
    if result.returncode != 0:
        # OpenSSL 3 needs -legacy for RC2-encrypted key material.
        arguments.insert(2, "-legacy")
        result = subprocess.run(arguments, capture_output=True)
        if result.returncode != 0:
            sys.stderr.write(result.stderr.decode("utf-8", "replace"))
            raise SystemExit("cannot read %s" % P12_PATH)

    with open(combined, "r", encoding="ascii") as handle:
        pem = handle.read()
    blocks = []
    current = []
    for line in pem.splitlines(keepends=True):
        if line.startswith("-----BEGIN "):
            current = [line]
        elif current:
            current.append(line)
            if line.startswith("-----END "):
                blocks.append("".join(current))
                current = []

    certificate = None
    private_key = None
    for block in blocks:
        if "BEGIN CERTIFICATE" in block and certificate is None:
            certificate = block
        elif "BEGIN PRIVATE KEY" in block or "BEGIN RSA PRIVATE KEY" in block:
            private_key = block
    if certificate is None or private_key is None:
        raise SystemExit("the .p12 does not contain a certificate and a private key")

    certificate_path = os.path.join(directory, "cert.pem")
    key_path = os.path.join(directory, "key.pem")
    with open(certificate_path, "w", encoding="ascii", newline="\n") as handle:
        handle.write(certificate)
    with open(key_path, "w", encoding="ascii", newline="\n") as handle:
        handle.write(private_key)
    return certificate_path, key_path


def profile_payload(path):
    with open(path, "rb") as handle:
        data = handle.read()
    start = data.find(b"<?xml")
    end = data.rfind(b"</plist>")
    if start == -1 or end == -1:
        raise SystemExit("%s is not a CMS-wrapped plist" % path)
    return data[start:end + len(b"</plist>")]


def bump_date(payload, year):
    key = b"<key>ExpirationDate</key>"
    index = payload.find(key)
    if index == -1:
        return payload, None
    start = payload.find(b"<date>", index)
    end = payload.find(b"</date>", start)
    if start == -1 or end == -1:
        return payload, None
    value = payload[start + len(b"<date>"):end]
    new_value = str(year).encode("ascii") + value[4:]
    if value == new_value:
        return payload, None
    return payload[:start + len(b"<date>")] + new_value + payload[end:], (
        value.decode("ascii", "replace"),
        new_value.decode("ascii", "replace"),
    )


def detect_source_bundle_id(profiles_directory):
    """The bundle id the bundled profiles were made for (from Telegram.mobileprovision)."""
    payload = profile_payload(os.path.join(profiles_directory, "Telegram.mobileprovision"))
    application_identifier = plistlib.loads(payload)["Entitlements"]["application-identifier"]
    return application_identifier.split(".", 1)[1]


def retarget_bundle_id(payload, source_bundle_id, target_bundle_id):
    """Replaces the bundle id everywhere in the profile plist (names, app ids, app groups)."""
    return payload.replace(source_bundle_id.encode("ascii"), target_bundle_id.encode("ascii"))


def verify(path):
    result = subprocess.run(
        [OPENSSL, "smime", "-inform", "der", "-verify", "-noverify", "-in", path],
        capture_output=True,
    )
    return result.returncode == 0, result.stderr.decode("utf-8", "replace")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--year", type=int, default=2036)
    parser.add_argument(
        "--check",
        action="store_true",
        help="only verify that the profiles are still readable/valid",
    )
    parser.add_argument(
        "--bundle-id",
        help="retarget the profiles to this bundle id (requires --out)",
    )
    parser.add_argument(
        "--from-bundle-id",
        help="bundle id the bundled profiles were made for (default: detected)",
    )
    parser.add_argument(
        "--out",
        help="write retargeted profiles/ and certs/ here instead of changing the bundled ones",
    )
    arguments = parser.parse_args()

    target_bundle_id = arguments.bundle_id
    if target_bundle_id is not None:
        if not arguments.out:
            parser.error("--bundle-id requires --out")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", target_bundle_id):
            parser.error("invalid bundle id %r" % target_bundle_id)
    elif arguments.out:
        parser.error("--out requires --bundle-id")

    if arguments.check:
        failed = False
        for path in sorted(glob.glob(os.path.join(PROFILES, "*.mobileprovision"))):
            ok, error = verify(path)
            print("%-42s %s" % (os.path.basename(path), "ok" if ok else "FAILED"))
            if not ok:
                print(error)
                failed = True
        raise SystemExit(1 if failed else 0)

    output_profiles = PROFILES
    source_bundle_id = None
    if target_bundle_id is not None:
        source_bundle_id = arguments.from_bundle_id or detect_source_bundle_id(PROFILES)
        output_profiles = os.path.join(arguments.out, "profiles")
        os.makedirs(output_profiles, exist_ok=True)
        shutil.copytree(os.path.join(FAKE_DIR, "certs"), os.path.join(arguments.out, "certs"), dirs_exist_ok=True)
        print("Retargeting profiles %s -> %s in %s" % (source_bundle_id, target_bundle_id, arguments.out))

    temporary = tempfile.mkdtemp()
    try:
        certificate_path, key_path = extract_certificate(temporary)
        changed = 0
        for path in sorted(glob.glob(os.path.join(PROFILES, "*.mobileprovision"))):
            name = os.path.basename(path)
            payload = profile_payload(path)
            if source_bundle_id is not None:
                payload = retarget_bundle_id(payload, source_bundle_id, target_bundle_id)
            payload, before_after = bump_date(payload, arguments.year)

            payload_path = os.path.join(temporary, name + ".plist")
            with open(payload_path, "wb") as handle:
                handle.write(payload)

            signed_path = os.path.join(temporary, name)
            run([
                OPENSSL, "smime", "-sign",
                "-in", payload_path,
                "-signer", certificate_path,
                "-inkey", key_path,
                "-outform", "der",
                "-nodetach",
                "-md", "sha256",
                "-out", signed_path,
            ])

            ok, error = verify(signed_path)
            if not ok:
                sys.stderr.write(error)
                raise SystemExit("re-signed %s does not verify" % name)

            shutil.copyfile(signed_path, os.path.join(output_profiles, name))
            if before_after is None:
                print("%-42s re-signed" % name)
            else:
                print("%-42s %s -> %s" % (name, before_after[0], before_after[1]))
                changed += 1

        print("Re-signed %d profile(s), bumped %d date(s) in %s" % (len(glob.glob(os.path.join(PROFILES, "*.mobileprovision"))), changed, output_profiles))
    finally:
        shutil.rmtree(temporary, ignore_errors=True)


if __name__ == "__main__":
    main()
