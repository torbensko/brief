#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
Scripts/build-app.sh
build/Brief.app/Contents/MacOS/Brief --check-recording-layout
build/Brief.app/Contents/MacOS/Brief --check-multiple-recordings
build/Brief.app/Contents/MacOS/Brief --check-cleanup-copy
build/Brief.app/Contents/MacOS/DictationWorker --self-test
