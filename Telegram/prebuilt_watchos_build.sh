#!/usr/bin/env bash
# Worker for the apple_prebuilt_watchos_application Bazel rule.
#
# Builds the tgwatch watch app via xcodebuild (device, Release, UNSIGNED), then
# — if a signing identity is supplied — codesigns the app and its nested
# frameworks with the Telegram distribution/development identity + the watchkitapp
# provisioning profile, and finally zips the .app into the rule's output archive.
#
# The host ios_application embeds this archive under Watch/ and re-seals the host;
# it does NOT re-sign the watch app, so the watch signing must happen here.
#
# Args:
#   $1 source_path  Absolute path to the exported tgwatch source tree (contains tgwatch.xcodeproj)
#   $2 output_zip   Path (declared by Bazel) to write the .app archive to
#   $3 api_id       TG_API_ID build setting
#   $4 api_hash     TG_API_HASH build setting
#   $5 identity     Codesigning identity (SHA1 hash); empty => unsigned build
#   $6 profile      Path to the watchkitapp .mobileprovision; empty => none
set -euo pipefail

SRC="$1"; OUT_ZIP="$2"; API_ID="$3"; API_HASH="$4"; IDENTITY="${5:-}"; PROFILE="${6:-}"; INFOPLIST_OUT="${7:-}"; VERSIONS_JSON="${8:-}"; BUILD_NUMBER="${9:-1}"

if [ ! -e "$SRC/tgwatch.xcodeproj" ]; then
  echo "error: no tgwatch.xcodeproj at watchAppSourcePath=$SRC (run tools/export-sources.sh first)" >&2
  exit 1
fi

# Match the host app's version (rules_apple requires the embedded watch app's
# CFBundleShortVersionString/CFBundleVersion to equal the parent's).
MARKETING_VERSION="0.1"
if [ -n "$VERSIONS_JSON" ]; then
  MARKETING_VERSION="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['app'])" "$VERSIONS_JSON")"
fi

DD="$(mktemp -d)"
trap 'rm -rf "$DD"' EXIT

xcodebuild \
  -project "$SRC/tgwatch.xcodeproj" \
  -scheme "tgwatch Watch App" \
  -configuration Release \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath "$DD" \
  -quiet \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  TG_API_ID="$API_ID" TG_API_HASH="$API_HASH" \
  MARKETING_VERSION="$MARKETING_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build 1>&2

APP="$(find "$DD/Build/Products" -maxdepth 2 -name 'tgwatch Watch App.app' -type d | head -1)"
if [ -z "$APP" ]; then
  echo "error: built watch .app not found under $DD/Build/Products" >&2
  exit 1
fi

# Expose the watch app's Info.plist (the host reads it to verify the companion
# bundle-id linkage). Codesigning does not alter Info.plist content, so capture it now.
if [ -n "$INFOPLIST_OUT" ]; then
  cp "$APP/Info.plist" "$INFOPLIST_OUT"
fi

if [ -n "$IDENTITY" ]; then
  if [ -z "$PROFILE" ]; then
    echo "error: a signing identity was given but no provisioning profile (set --define=watchProvisioningProfile=<abs path>)" >&2
    exit 1
  fi
  cp "$PROFILE" "$APP/embedded.mobileprovision"
  ENT="$(mktemp)"
  trap 'rm -rf "$DD" "$ENT" "$ENT.plist"' EXIT
  security cms -D -i "$APP/embedded.mobileprovision" > "$ENT.plist"
  if ! /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$ENT.plist" > "$ENT" 2>/dev/null; then
    echo "error: provisioning profile has no Entitlements key: $PROFILE" >&2
    exit 1
  fi
  # Sign inside-out: nested frameworks first, then the app bundle.
  if [ -d "$APP/Frameworks" ]; then
    for fw in "$APP/Frameworks/"*; do
      [ -e "$fw" ] || continue
      codesign --force --timestamp=none --sign "$IDENTITY" "$fw" 1>&2
    done
  fi
  codesign --force --timestamp=none --sign "$IDENTITY" --entitlements "$ENT" "$APP" 1>&2
  codesign --verify --deep --strict "$APP" 1>&2
fi

# $OUT_ZIP is execroot-relative; the action's cwd is the execroot, so do NOT cd
# (that would resolve $OUT_ZIP against the DerivedData dir). --keepParent makes the
# archive root the .app itself even when $APP is an absolute path.
rm -f "$OUT_ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$OUT_ZIP"
