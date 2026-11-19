#!/usr/bin/env python3
"""Fetches the Python 3.11 iOS runtime for TrollGram plugins.

Produces:

  third-party/python/Python.xcframework    linked into the app (device + simulator)
  third-party/python/resources/python.zip  stdlib, unzipped on first launch

The stdlib ships as a single zip because Bazel flattens resource filegroups:
one archive is predictable, fast to build and easy to verify.

Usage:

    python3 build-system/setup_python.py [--python-revision 3.11-b13]
"""

import argparse
import os
import shutil
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

REVISION = "3.11-b13"
VERSION = "3.11"
URL_TEMPLATE = "https://github.com/beeware/Python-Apple-support/releases/download/{rev}/Python-{ver}-iOS-support.{rev_short}.tar.gz"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THIRD_PARTY = os.path.join(ROOT, "third-party", "python")
RESOURCES = os.path.join(THIRD_PARTY, "resources")
STDLIB_ZIP = os.path.join(RESOURCES, "python.zip")


def download(url, destination):
    print("Downloading", url)
    with urllib.request.urlopen(url, timeout=600) as response, open(destination, "wb") as handle:
        shutil.copyfileobj(response, handle)


def build_stdlib_zip(stdlib_source):
    """Zips `python3.11/` so that PYTHONHOME sees `lib/python3.11`."""
    os.makedirs(RESOURCES, exist_ok=True)
    if os.path.exists(STDLIB_ZIP):
        os.remove(STDLIB_ZIP)
    count = 0
    with zipfile.ZipFile(STDLIB_ZIP, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for directory, dirnames, filenames in os.walk(stdlib_source):
            dirnames[:] = [name for name in dirnames if name != "__pycache__"]
            for filename in filenames:
                if filename.endswith((".pyc", ".so", ".dylib")):
                    continue
                full_path = os.path.join(directory, filename)
                relative = os.path.relpath(full_path, stdlib_source)
                archive.write(full_path, os.path.join("lib", "python3.11", relative))
                count += 1

        # exteraGram SDK shims (base_plugin, client_utils, ui.settings, ...) live
        # at the archive root so `import base_plugin` works out of the box.
        sdk_source = os.path.join(ROOT, "Swiftgram", "PythonPlugins", "stdlib")
        if os.path.isdir(sdk_source):
            for directory, dirnames, filenames in os.walk(sdk_source):
                dirnames[:] = [name for name in dirnames if name != "__pycache__"]
                for filename in filenames:
                    if not filename.endswith(".py"):
                        continue
                    full_path = os.path.join(directory, filename)
                    relative = os.path.relpath(full_path, sdk_source)
                    archive.write(full_path, relative)
                    count += 1

    size_mb = os.path.getsize(STDLIB_ZIP) / (1024 * 1024)
    print("Packed %d stdlib files into %s (%.1f MB)" % (count, STDLIB_ZIP, size_mb))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--python-revision", default=REVISION)
    args = parser.parse_args()

    revision = args.python_revision
    revision_short = revision.split("-")[-1]
    url = URL_TEMPLATE.format(rev=revision, ver=VERSION, rev_short=revision_short)

    os.makedirs(THIRD_PARTY, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        archive = os.path.join(tmp, "python.tar.gz")
        download(url, archive)

        extract_dir = os.path.join(tmp, "extract")
        with tarfile.open(archive, "r:gz") as tar:
            tar.extractall(extract_dir)

        framework = os.path.join(extract_dir, "Python.xcframework")
        if not os.path.isdir(framework):
            print("Python.xcframework not found in archive", file=sys.stderr)
            sys.exit(1)

        target = os.path.join(THIRD_PARTY, "Python.xcframework")
        if os.path.isdir(target):
            shutil.rmtree(target)
        # Dylibs cannot be extracted on Windows hosts and are not linked (the
        # app links Python.framework, which ships its own binary).
        skipped = shutil.ignore_patterns("*.dylib", "*.so", "__pycache__", "*.pyc")
        shutil.copytree(framework, target, ignore=skipped)
        print("Installed", target)

        stdlib_source = os.path.join(framework, "lib", "python3.11")
        if not os.path.isdir(stdlib_source):
            print("python3.11 stdlib not found in", framework, file=sys.stderr)
            sys.exit(1)
        build_stdlib_zip(stdlib_source)


if __name__ == "__main__":
    main()
