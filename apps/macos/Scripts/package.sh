#!/bin/bash
# Builds the release app for Apple silicon and Intel and packs it into the
# disk image people download: build/WallVue-<version>.dmg
# Usage: Scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
DMG="build/WallVue-$VERSION.dmg"

UNIVERSAL=1 ./Scripts/build-app.sh release

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/WallVue.app "$STAGE/WallVue.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me First.txt" <<TXT
WallVue $VERSION

1. Drag WallVue onto the Applications folder.
2. Open WallVue from Applications.
3. The first time, macOS says it can't check the app, because WallVue is
   free software built without a paid Apple developer certificate.
   Open System Settings > Privacy & Security, scroll down, and click
   "Open Anyway" next to WallVue. You only do this once.

WallVue is open source under the MIT licence:
https://github.com/suyashjain004/WallVue
TXT

rm -f "$DMG"
hdiutil create -volname "WallVue $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Packaged $DMG"
lipo -archs build/WallVue.app/Contents/MacOS/WallVue
shasum -a 256 "$DMG"
