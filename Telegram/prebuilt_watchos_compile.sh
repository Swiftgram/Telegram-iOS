#!/usr/bin/env bash
# Compile worker for the apple_prebuilt_watchos_application Bazel rule (action 1 of 2).
#
# Builds the tgwatch watch app via xcodebuild (device, Release, UNSIGNED) with
# PLACEHOLDER version/api values, then zips the .app into the rule's intermediate
# archive. It deliberately depends only on the watch source snapshot — version,
# build number, api id/hash and signing are all applied later by
# prebuilt_watchos_patch.sh, so this (expensive, ~4-min) action stays cached across
# version/build/identity changes.
#
# Args:
#   $1 source_path  Execroot-relative path to the committed in-repo snapshot
#                   (Telegram/WatchApp), which contains tgwatch.xcodeproj.
#   $2 output_zip   Path (declared by Bazel) to write the unsigned .app archive to.
set -euo pipefail

SRC="$1"; OUT_ZIP="$2"

if [ ! -e "$SRC/tgwatch.xcodeproj" ]; then
  echo "error: no tgwatch.xcodeproj at $SRC (re-sync the Telegram/WatchApp snapshot via tgwatch/tools/export-sources.sh)" >&2
  exit 1
fi

DD="$(mktemp -d)"
trap 'rm -rf "$DD"' EXIT

# Build from a writable copy so xcodebuild/SwiftPM never write into the (possibly
# in-repo, read-only) source tree — e.g. SwiftPM's Package.resolved or the workspace.
# The tree is small (~12M); a plain cp on each (uncached) build is acceptable.
WORKSRC="$DD/src"
mkdir -p "$WORKSRC"
cp -R "$SRC/." "$WORKSRC/"

# Version/api are placeholders here; prebuilt_watchos_patch.sh overwrites the four
# Info.plist keys afterward. They only ever land in the Info.plist (via $(...)
# substitution and a runtime Bundle.main lookup), never in the compiled binary, so
# the build output is independent of them.
xcodebuild \
  -project "$WORKSRC/tgwatch.xcodeproj" \
  -scheme "tgwatch Watch App" \
  -configuration Release \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath "$DD" \
  -quiet \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  TG_API_ID=0 TG_API_HASH=placeholder \
  MARKETING_VERSION=0.0 CURRENT_PROJECT_VERSION=0 \
  build 1>&2

APP="$(find "$DD/Build/Products" -maxdepth 2 -name 'tgwatch Watch App.app' -type d | head -1)"
if [ -z "$APP" ]; then
  echo "error: built watch .app not found under $DD/Build/Products" >&2
  exit 1
fi

# $OUT_ZIP is execroot-relative; the action's cwd is the execroot, so do NOT cd
# (that would resolve $OUT_ZIP against the DerivedData dir). --keepParent makes the
# archive root the .app itself even when $APP is an absolute path.
rm -f "$OUT_ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$OUT_ZIP"
