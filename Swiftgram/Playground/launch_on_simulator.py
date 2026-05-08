#!/usr/bin/env python3

import subprocess
import json
import os
import time


def find_app(start_path):
    for root, dirs, _ in os.walk(start_path):
        for dir in dirs:
            if dir.endswith(".app"):
                return os.path.join(root, dir)
    return None


def ensure_simulator_booted(device_name) -> str:
    # List all devices
    devices_json = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "--json"]
    ).decode()
    devices = json.loads(devices_json)
    for runtime in devices["devices"]:
        for device in devices["devices"][runtime]:
            if device["name"] == device_name:
                device_udid = device["udid"]
                if device["state"] == "Booted":
                    print(f"Simulator {device_name} is already booted.")
                    return device_udid
                break
        if device_udid:
            break

    if not device_udid:
        raise Exception(f"Simulator {device_name} not found")

    # Boot the device
    print(f"Booting simulator {device_name}...")
    subprocess.run(["xcrun", "simctl", "boot", device_udid], check=True)

    # Wait for the device to finish booting
    print("Waiting for simulator to finish booting...")
    while True:
        boot_status = subprocess.check_output(
            ["xcrun", "simctl", "list", "devices"]
        ).decode()
        if f"{device_name} ({device_udid}) (Booted)" in boot_status:
            break
        time.sleep(0.5)

    print(f"Simulator {device_name} is now booted.")
    return device_udid


def build_and_run_xcode_project(project_path, scheme_name, destination):
    # Change to the directory containing the .xcodeproj file
    os.chdir(os.path.dirname(project_path))

    # Build the project
    build_command = [
        "xcodebuild",
        "-project",
        project_path,
        "-scheme",
        scheme_name,
        "-destination",
        destination,
        "-sdk",
        "iphonesimulator",
        "build",
    ]

    try:
        subprocess.run(build_command, check=True)
        print("Build successful!")
    except subprocess.CalledProcessError as e:
        print(f"Build failed with error: {e}")
        return

    # Get the bundle identifier and app path
    settings_command = [
        "xcodebuild",
        "-project",
        project_path,
        "-scheme",
        scheme_name,
        "-sdk",
        "iphonesimulator",
        "-showBuildSettings",
    ]

    try:
        result = subprocess.run(
            settings_command, capture_output=True, text=True, check=True
        )
        settings = result.stdout.split("\n")
        bundle_id = next(
            line.split("=")[1].strip()
            for line in settings
            if "PRODUCT_BUNDLE_IDENTIFIER" in line
        )
        build_dir = next(
            line.split("=")[1].strip()
            for line in settings
            if "TARGET_BUILD_DIR" in line
        )

        app_path = find_app(build_dir)
        if not app_path:
            print(f"Could not find .app file in {build_dir}")
            return
        print(f"Found app at: {app_path}")
        print(f"Bundle identifier: {bundle_id}")
        print(f"App path: {app_path}")
    except (subprocess.CalledProcessError, StopIteration) as e:
        print(f"Failed to get build settings: {e}")
        return

    device_udid = ensure_simulator_booted(simulator_name)

    # Install the app on the simulator
    install_command = ["xcrun", "simctl", "install", device_udid, app_path]

    try:
        subprocess.run(install_command, check=True)
        print("App installed on simulator successfully!")
    except subprocess.CalledProcessError as e:
        print(f"Failed to install app on simulator: {e}")
        return

    # List installed apps
    try:
        listapps_cmd = "/usr/bin/xcrun simctl listapps booted | /usr/bin/plutil -convert json -r -o - -- -"
        result = subprocess.run(
            listapps_cmd, shell=True, capture_output=True, text=True, check=True
        )
        apps = json.loads(result.stdout)

        if bundle_id in apps:
            print(f"App {bundle_id} is installed on the simulator")
        else:
            print(f"App {bundle_id} is not installed on the simulator")
            print("Installed apps:", list(apps.keys()))
    except subprocess.CalledProcessError as e:
        print(f"Failed to list apps: {e}")
    except json.JSONDecodeError as e:
        print(f"Failed to parse app list: {e}")

    # Focus simulator
    subprocess.run(["open", "-a", "Simulator"], check=True)

    # Run the project on the simulator
    run_command = ["xcrun", "simctl", "launch", "booted", bundle_id]

    try:
        subprocess.run(run_command, check=True)
        print("Application launched in simulator!")
    except subprocess.CalledProcessError as e:
        print(f"Failed to launch application in simulator: {e}")


# Usage
current_script_dir = os.path.dirname(os.path.abspath(__file__))
project_path = os.path.join(current_script_dir, "Playground.xcodeproj")
scheme_name = "Playground"
simulator_name = "iPhone 15"
destination = f"platform=iOS Simulator,name={simulator_name},OS=latest"

if __name__ == "__main__":
    build_and_run_xcode_project(project_path, scheme_name, destination)
