#!/usr/bin/env bash
# Patch + sign worker for the apple_prebuilt_watchos_application Bazel rule (action 2 of 2).
#
# Takes the unsigned, placeholder-version watch .app archive produced by
# prebuilt_watchos_compile.sh, rewrites the four per-build Info.plist values
# (CFBundleShortVersionString, CFBundleVersion, TG_API_ID, TG_API_HASH) — none of
# which affect the compiled binary — then — if a provisioning profile is supplied —
# codesigns the app and its nested frameworks with the watchkitapp provisioning
# profile and a matching identity, and finally zips the .app into the rule's output
# archive.
#
# Splitting this from the compile step lets Bazel cache the (expensive) xcodebuild
# whenever only the version/build number/api/identity change.
#
# The host ios_application embeds this archive under Watch/ and re-seals the host;
# it does NOT re-sign the watch app, so the watch signing must happen here.
#
# Args:
#   $1 input_zip      Compiled (unsigned, placeholder-version) .app archive from action 1
#   $2 output_zip     Path (declared by Bazel) to write the final .app archive to
#   $3 api_id         TG_API_ID Info.plist value
#   $4 api_hash       TG_API_HASH Info.plist value
#   $5 identity       Codesigning identity (SHA1 hash); empty => derived from $6's cert
#   $6 profile        Path to the watchkitapp .mobileprovision; empty => unsigned build
#   $7 infoplist_out  Path (declared by Bazel) to copy the patched Info.plist to
#   $8 versions_json  versions.json (key 'app' => CFBundleShortVersionString)
#   $9 build_number   CFBundleVersion
set -euo pipefail

IN_ZIP="$1"; OUT_ZIP="$2"; API_ID="$3"; API_HASH="$4"; IDENTITY="${5:-}"; PROFILE="${6:-}"; INFOPLIST_OUT="${7:-}"; VERSIONS_JSON="${8:-}"; BUILD_NUMBER="${9:-1}"

# Match the host app's version (rules_apple requires the embedded watch app's
# CFBundleShortVersionString/CFBundleVersion to equal the parent's).
MARKETING_VERSION="0.1"
if [ -n "$VERSIONS_JSON" ]; then
  MARKETING_VERSION="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['app'])" "$VERSIONS_JSON")"
fi

DD="$(mktemp -d)"
trap 'rm -rf "$DD"' EXIT

/usr/bin/ditto -x -k "$IN_ZIP" "$DD"
APP="$(find "$DD" -maxdepth 2 -name 'tgwatch Watch App.app' -type d | head -1)"
if [ -z "$APP" ]; then
  echo "error: compiled watch .app not found inside $IN_ZIP" >&2
  exit 1
fi

# Overwrite the placeholder values baked in at compile time. All four keys already
# exist in the compiled (binary-format) Info.plist, so PlistBuddy Set preserves their
# (string) type — matching what $(...) substitution produced and what Secrets.swift
# expects from Bundle.main.object(forInfoDictionaryKey:).
PLIST="$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :TG_API_ID $API_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :TG_API_HASH $API_HASH" "$PLIST"

# Expose the patched watch Info.plist (the host reads it to verify the companion
# bundle-id linkage and the child version). Codesigning does not alter Info.plist
# content, so capture it now.
if [ -n "$INFOPLIST_OUT" ]; then
  cp "$PLIST" "$INFOPLIST_OUT"
fi

if [ -n "$IDENTITY" ] && [ -z "$PROFILE" ]; then
  echo "error: a signing identity was given but no provisioning profile (set --watchProvisioningProfile=<abs path>)" >&2
  exit 1
fi

# Sign the watch app whenever a provisioning profile is available. When no explicit
# identity is supplied, derive it from the certificate embedded in that profile, so
# the watch app is signed with the same distribution/development identity as the host
# app (resolved from the shared codesigning material) — required for App Store, where
# every nested bundle must carry the Apple submission certificate. Without a profile
# the app is left unsigned (the host does not re-sign it).
if [ -n "$PROFILE" ]; then
  cp "$PROFILE" "$APP/embedded.mobileprovision"
  ENT="$(mktemp)"
  trap 'rm -rf "$DD" "$ENT" "$ENT.plist"' EXIT
  security cms -D -i "$APP/embedded.mobileprovision" > "$ENT.plist"
  if ! /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$ENT.plist" > "$ENT" 2>/dev/null; then
    echo "error: provisioning profile has no Entitlements key: $PROFILE" >&2
    exit 1
  fi

  if [ -z "$IDENTITY" ]; then
    # The identity is the SHA-1 of the profile's first embedded certificate, which is
    # exactly how codesign / the keychain reference it. The matching private key must
    # be in the keychain (it is: the same cert signs the host app).
    IDENTITY="$(python3 -c "import sys,plistlib,subprocess,hashlib; d=plistlib.loads(subprocess.run(['security','cms','-D','-i',sys.argv[1]],capture_output=True).stdout); print(hashlib.sha1(d['DeveloperCertificates'][0]).hexdigest().upper())" "$APP/embedded.mobileprovision")"
    if [ -z "$IDENTITY" ]; then
      echo "error: could not derive a signing identity from the provisioning profile (no DeveloperCertificates): $PROFILE" >&2
      exit 1
    fi
    echo "note: signing watch app with identity $IDENTITY derived from $(basename "$PROFILE")" >&2
  fi

  # Distribution profiles (App Store / Ad Hoc) set get-task-allow=false and require a
  # secure timestamp; development builds set it true and can skip the timestamp (faster,
  # no round-trip to Apple's timestamp service).
  TS_FLAG="--timestamp"
  if /usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$ENT" 2>/dev/null | grep -qi '^true$'; then
    TS_FLAG="--timestamp=none"
  fi

  # Sign inside-out: nested frameworks first, then the app bundle.
  if [ -d "$APP/Frameworks" ]; then
    for fw in "$APP/Frameworks/"*; do
      [ -e "$fw" ] || continue
      codesign --force "$TS_FLAG" --sign "$IDENTITY" "$fw" 1>&2
    done
  fi
  codesign --force "$TS_FLAG" --sign "$IDENTITY" --entitlements "$ENT" "$APP" 1>&2
  codesign --verify --deep --strict "$APP" 1>&2
else
  echo "warning: no watch provisioning profile supplied; the watch app will be UNSIGNED and will be rejected by the App Store. Pass --watchProvisioningProfile, or build with codesigning material that includes the watchkitapp profile." >&2
fi

# $OUT_ZIP is execroot-relative; the action's cwd is the execroot, so do NOT cd
# (that would resolve $OUT_ZIP against the temp dir). --keepParent makes the archive
# root the .app itself even when $APP is an absolute path.
rm -f "$OUT_ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$OUT_ZIP"
