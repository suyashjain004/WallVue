#!/bin/bash
# Builds the Swift package and wraps the binary in a runnable .app bundle.
# Usage: Scripts/build-app.sh [debug|release]
#   UNIVERSAL=1  build for both Apple silicon and Intel (needs Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="WallVue"
BUNDLE_ID="io.github.wallvue"
VERSION="$(tr -d '[:space:]' < VERSION)"
# The number of commits makes a build number that always goes up.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
CONFIG="${1:-release}"

ARCHS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCHS=(--arch arm64 --arch x86_64); fi

swift build -c "$CONFIG" --product WallVueApp ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/WallVueApp"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Video or Image</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.movie</string>
                <string>public.image</string>
            </array>
        </dict>
    </array>
    <key>NSHumanReadableCopyright</key><string>MIT licensed. Free and open source.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: the app runs, but macOS asks the person who downloaded
# it to approve it once (System Settings → Privacy & Security → Open Anyway).
codesign --force --sign - "$APP"
echo "Built $APP ($VERSION, build $BUILD)"
