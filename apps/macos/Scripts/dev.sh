#!/bin/bash
# Development loop: test, build the app bundle, and write logs where they
# can be read back. Usage: Scripts/dev.sh [debug|release]
set -uo pipefail
cd "$(dirname "$0")/.."
LOG="../../.transfer"
mkdir -p "$LOG"
swift test > "$LOG/test.log" 2>&1; echo "EXIT:$?" >> "$LOG/test.log"
./Scripts/build-app.sh "${1:-release}" > "$LOG/app.log" 2>&1; echo "EXIT:$?" >> "$LOG/app.log"
