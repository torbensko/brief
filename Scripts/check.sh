#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
Scripts/build-app.sh
build/Brief.app/Contents/MacOS/DictationWorker --self-test
