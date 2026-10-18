#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-debug}"
# A stable development identity lets macOS retain privacy permissions across rebuilds.
# Respect explicit selection (including '-' for an intentionally ad-hoc build).
identity="${SIGNING_IDENTITY:-}"
if [ -z "$identity" ]; then
    identities="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2 }')"
    count="$(printf '%s\n' "$identities" | awk 'NF { n++ } END { print n+0 }')"
    if [ "$count" = 1 ]; then
        identity="$identities"
    else
        identity="-"
        echo "No unique Apple Development identity. Using ad-hoc signing; macOS permissions may need renewal after rebuilding. Set SIGNING_IDENTITY to choose a stable identity."
    fi
fi
swift build -c "$configuration"
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
app="$PWD/build/Brief.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(cat VERSION)" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$app/Contents/Info.plist"
Scripts/build-icon.sh
cp build/Brief.icns "$app/Contents/Resources/Brief.icns"
cp "$bin_dir/Brief" "$bin_dir/DictationWorker" "$app/Contents/MacOS/"
# SwiftPM dependencies can include resource bundles needed at runtime.
for bundle in "$bin_dir"/*.bundle; do
    [ -d "$bundle" ] || continue
    ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"
done
# Swift 6.4's Xcode build backend compiles the MLX shader resource bundle.
metal_library="$(find "$bin_dir" -name default.metallib -print -quit)"
if [ -z "$metal_library" ]; then
    echo "Missing MLX Metal shaders. Use Swift 6.4 with the Xcode build backend and install the Metal Toolchain." >&2
    exit 1
fi
cp "$metal_library" "$app/Contents/Resources/mlx.metallib"
sign_options=(--force --sign "$identity")
if [ "${DISTRIBUTION:-0}" = 1 ]; then sign_options+=(--options runtime --timestamp); fi
codesign "${sign_options[@]}" "$app/Contents/MacOS/DictationWorker"
codesign "${sign_options[@]}" "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
