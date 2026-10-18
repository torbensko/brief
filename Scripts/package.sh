#!/bin/bash
# Local preview: ./scripts/package.sh --unsigned
# Distribution: SIGNING_IDENTITY and Apple credentials must be present.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-release}"
[[ "$MODE" == release || "$MODE" == --unsigned ]] || { echo 'Usage: package.sh [--unsigned]' >&2; exit 1; }
if [[ "$MODE" == release ]]; then
  : "${SIGNING_IDENTITY:?Developer ID Application signing identity is required}"
  : "${APPLE_ID:?Missing APPLE_ID}"
  : "${APPLE_ID_PASSWORD:?Missing APPLE_ID_PASSWORD}"
  : "${APPLE_TEAM_ID:?Missing APPLE_TEAM_ID}"
  [[ "$SIGNING_IDENTITY" == 'Developer ID Application:'* ]] || { echo 'A Developer ID Application certificate is required.' >&2; exit 1; }
else
  export SIGNING_IDENTITY=-
fi
CONFIGURATION=release DISTRIBUTION="$([[ "$MODE" == release ]] && echo 1 || echo 0)" ./Scripts/build-app.sh
APP="$PWD/build/Brief.app"
[[ "$(uname -m)" == arm64 ]] || { echo 'Brief requires an Apple Silicon build host.' >&2; exit 1; }
mkdir -p dist
STAGE="$(mktemp -d "$PWD/dist/package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
notarize() {
  local archive="$1" result="$2"
  xcrun notarytool submit "$archive" --apple-id "$APPLE_ID" --password "$APPLE_ID_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" --wait --timeout 30m --output-format json > "$result"
  python3 - "$result" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if r.get('status') != 'Accepted':
    sys.exit(f"Notarization {r.get('id')}: {r.get('status')}. Retrieve the notarytool log before retrying.")
PY
}
if [[ "$MODE" == release ]]; then
  ditto -c -k --keepParent "$APP" "$STAGE/submission.zip"
  notarize "$STAGE/submission.zip" "$PWD/dist/notary-app.json"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose "$APP"
fi
mkdir -p "$STAGE/image"
ditto "$APP" "$STAGE/image/Brief.app"
ln -s /Applications "$STAGE/image/Applications"
cp README.md "$STAGE/image/README.md"
cp LICENSE "$STAGE/image/LICENSE.txt"
SUFFIX=''
if [[ "$MODE" == --unsigned ]]; then SUFFIX='-unsigned'; fi
DMG="$PWD/dist/Brief${SUFFIX}.dmg"
ZIP="$PWD/dist/Brief${SUFFIX}.zip"
hdiutil create -volname 'Brief' -srcfolder "$STAGE/image" -ov -format UDZO "$DMG"
if [[ "$MODE" == release ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
  notarize "$DMG" "$PWD/dist/notary-dmg.json"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi
ditto -c -k --keepParent "$APP" "$ZIP"
(cd dist && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > "SHA256SUMS${SUFFIX}.txt")
echo "Packaged: $DMG"
