#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/Apollo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Apollo" "$APP/Contents/MacOS/Apollo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Demo.lrc "$APP/Contents/Resources/Demo.lrc"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
/usr/bin/codesign --force --sign "${SIGNING_IDENTITY:--}" --options runtime --entitlements Resources/Apollo.entitlements "$APP"
/usr/bin/codesign --verify --strict "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" dist/Apollo-macOS.zip
echo "Built $APP and dist/Apollo-macOS.zip"
