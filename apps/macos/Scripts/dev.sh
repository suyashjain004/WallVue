#!/bin/bash
# Development loop: test, build the app bundle, and write logs where they
# can be read back. Usage: Scripts/dev.sh [debug|release]
set -uo pipefail
cd "$(dirname "$0")/.."
LOG="../../.transfer"
mkdir -p "$LOG"
# The loop maker's export test needs a real video; use a sample if one is there.
SAMPLE="$(ls "$PWD/$LOG"/samples/*.mp4 2>/dev/null | head -1)"
if [ -n "$SAMPLE" ]; then export WALLVUE_SAMPLE_VIDEO="$SAMPLE"; fi
swift test > "$LOG/test.log" 2>&1; echo "EXIT:$?" >> "$LOG/test.log"
./Scripts/build-app.sh "${1:-release}" > "$LOG/app.log" 2>&1; echo "EXIT:$?" >> "$LOG/app.log"
