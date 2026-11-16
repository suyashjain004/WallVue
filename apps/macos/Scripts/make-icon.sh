#!/bin/bash
# Regenerates Resources/AppIcon.icns from Scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Resources
TMP="$(mktemp -d)/AppIcon.iconset"
swift Scripts/make-icon.swift "$TMP"
iconutil -c icns "$TMP" -o Resources/AppIcon.icns
cp "$TMP/icon_512x512.png" Resources/AppIcon-preview.png
echo "Wrote Resources/AppIcon.icns"
