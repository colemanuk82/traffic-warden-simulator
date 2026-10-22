#!/usr/bin/env bash
# Builds the Windows release: TrafficWardenSim.exe, a portable zip and the installer.
# Needs Godot 4.3 (GODOT=path) with the 4.3 export templates installed, plus makensis (NSIS) and zip.
# Usage: tools/build_release.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-1.0.0}"
GODOT="${GODOT:-godot}"
OUT=build
rm -rf "$OUT" && mkdir -p "$OUT/windows" "$OUT/linux" "$OUT/release"

# Audio and fonts are loaded from raw files at runtime (AudioStreamOggVorbis.load_from_file,
# FontFile.load_dynamic_font), so tell Godot to pack them as-is instead of importing them.
find audio fonts -type f \( -name '*.ogg' -o -name '*.ttf' \) | while read -r f; do
	printf '[remap]\n\nimporter="keep"\n' > "$f.import"
done

"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-release "Windows Desktop" "$OUT/windows/TrafficWardenSim.exe"
"$GODOT" --headless --export-release "Linux (test)" "$OUT/linux/TrafficWardenSim.x86_64"

# Portable zip
PORT="$OUT/Traffic Warden Sim"
mkdir -p "$PORT"
cp "$OUT/windows/TrafficWardenSim.exe" "$PORT/"
cp fonts/*.txt "$PORT/"
cp installer/README.txt "$PORT/README.txt"
(cd "$OUT" && zip -qr "release/TrafficWardenSim-$VERSION-windows-portable.zip" "Traffic Warden Sim")

# Installer
makensis -V2 -DVERSION="$VERSION" -DSRC="$(pwd)/$OUT/Traffic Warden Sim" \
	-DOUTFILE="$(pwd)/$OUT/release/TrafficWardenSim-$VERSION-setup.exe" "$(pwd)/installer/installer.nsi"

ls -la "$OUT/release"
