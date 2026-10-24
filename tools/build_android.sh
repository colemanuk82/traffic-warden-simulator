#!/usr/bin/env bash
# Builds the signed Android APK: build/release/TrafficWardenSim-<version>.apk
# Needs Godot 4.3 (GODOT=path) with the 4.3 export templates, and in Godot's editor settings an
# Android SDK path holding build-tools/<any>/apksigner and platform-tools/adb.
# The signing key never goes in the repo. Pass it in with:
#   ANDROID_KEYSTORE=/path/to/file.keystore ANDROID_KEY_ALIAS=trafficwarden ANDROID_KEY_PASSWORD=...
# Keep using the same keystore: Android only installs an update signed with the same key.
# Usage: tools/build_android.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-1.1.0}"
GODOT="${GODOT:-godot}"
: "${ANDROID_KEYSTORE:?set ANDROID_KEYSTORE to the release keystore}"
: "${ANDROID_KEY_PASSWORD:?set ANDROID_KEY_PASSWORD}"
mkdir -p build/android build/release

# Audio and fonts are loaded from raw files at runtime, so pack them as-is (see build_release.sh)
find audio fonts -type f \( -name '*.ogg' -o -name '*.ttf' \) | while read -r f; do
	printf '[remap]\n\nimporter="keep"\n' > "$f.import"
done

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$ANDROID_KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${ANDROID_KEY_ALIAS:-trafficwarden}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$ANDROID_KEY_PASSWORD"
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-release "Android" "build/android/TrafficWardenSim.apk"
cp build/android/TrafficWardenSim.apk "build/release/TrafficWardenSim-$VERSION.apk"
ls -la build/release/*.apk
