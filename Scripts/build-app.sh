#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-debug}"
swift build -c "$configuration"
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
app="$PWD/build/LocalDictation.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$bin_dir/LocalDictation" "$bin_dir/DictationWorker" "$app/Contents/MacOS/"
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
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app/Contents/MacOS/DictationWorker"
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
