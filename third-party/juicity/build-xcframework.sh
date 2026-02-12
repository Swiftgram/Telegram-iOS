#!/bin/bash
# Build script for juicity Go bridge -> iOS xcframework
# Requirements: Go 1.21+, gomobile (go install golang.org/x/mobile/cmd/gomobile@latest)
#
# Usage: ./build-xcframework.sh
# Output: JuicityBridge.xcframework in the current directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOBRIDGE_DIR="${SCRIPT_DIR}/gobridge"
OUTPUT_DIR="${SCRIPT_DIR}"

echo "==> Initializing gomobile..."
gomobile init

echo "==> Building JuicityBridge.xcframework..."
cd "${GOBRIDGE_DIR}"

gomobile bind \
    -target=ios \
    -o "${OUTPUT_DIR}/JuicityBridge.xcframework" \
    -iosversion=13.0 \
    .

echo "==> Done! Output: ${OUTPUT_DIR}/JuicityBridge.xcframework"
echo "    Copy this to your project and add it as a dependency."
