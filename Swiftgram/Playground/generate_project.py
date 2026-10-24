#!/usr/bin/env python3

from contextlib import contextmanager
import os
import subprocess
import sys
import shutil
import textwrap

# Import the locate_bazel function
sys.path.append(
    os.path.join(os.path.dirname(__file__), "..", "..", "build-system", "Make")
)
from BazelLocation import locate_bazel


@contextmanager
def cwd(path):
    oldpwd = os.getcwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(oldpwd)


def main():
    # Get the current script directory
    current_script_dir = os.path.dirname(os.path.abspath(__file__))
    with cwd(os.path.join(current_script_dir, "..", "..")):
        bazel_path = locate_bazel(os.getcwd(), cache_host=None)
    # 1. Kill all Xcode processes
    subprocess.run(["killall", "Xcode"], check=False)

    # 2. Delete xcodeproj.bazelrc if it exists and write a new one
    bazelrc_path = os.path.join(current_script_dir, "..", "..", "xcodeproj.bazelrc")
    if os.path.exists(bazelrc_path):
        os.remove(bazelrc_path)

    with open(bazelrc_path, "w") as f:
        f.write(
            textwrap.dedent(
                """
                build --announce_rc
                build --features=swift.use_global_module_cache
                build --verbose_failures
                build --features=swift.enable_batch_mode
                build --features=-swift.debug_prefix_map
                # build --disk_cache=

                build --swiftcopt=-no-warnings-as-errors
                build --copt=-Wno-error
                """
            )
        )

    # 3. Delete the Xcode project if it exists
    xcode_project_path = os.path.join(current_script_dir, "Playground.xcodeproj")
    if os.path.exists(xcode_project_path):
        shutil.rmtree(xcode_project_path)

    # 4. Write content to generate_project.py
    generate_project_path = os.path.join(current_script_dir, "custom_bazel_path.bzl")
    with open(generate_project_path, "w") as f:
        f.write("def custom_bazel_path():\n")
        f.write(f'    return "{bazel_path}"\n')

    # 5. Run xcodeproj generator
    working_dir = os.path.join(current_script_dir, "..", "..")
    bazel_command = f'"{bazel_path}" run //Swiftgram/Playground:Playground_xcodeproj'
    subprocess.run(bazel_command, shell=True, cwd=working_dir, check=True)

    # 5. Open Xcode project
    subprocess.run(["open", xcode_project_path], check=True)


if __name__ == "__main__":
    main()
