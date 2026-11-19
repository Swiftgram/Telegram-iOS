# Python 3.11 runtime (Python.xcframework)

Not tracked in git (binaries). Fetch it with:

    python3 build-system/setup_python.py

That script downloads the official Python-Apple-support 3.11 iOS build and
provisions:

| path | purpose |
| --- | --- |
| `third-party/python/Python.xcframework/` | static `Python.framework` slices (device arm64 + simulator) |
| `build/python-ios/python3.11/` | shared stdlib, copied into the app bundle |

Bazel target: `//third-party/python:Python`.

Bundling into the app happens in `Telegram/BUILD` (`python_stdlib` filegroup
plus `PYTHONHOME` set by `EmbeddedPython`).
