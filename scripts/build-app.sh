#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
# swift build does not compile .metal resources (swiftlang/swift-package-manager#7716);
# precompile the stitchable fisheye shader into the resource bundle for the shipped app.
BUNDLE="$BIN_DIR/Apollo_Apollo.bundle"
mkdir -p "$BUNDLE"
if [ ! -f "$BUNDLE/default.metallib" ]; then
  TMP="$(mktemp -d)"
  xcrun metal -c Sources/Apollo/Shaders/Fisheye.metal -o "$TMP/Fisheye.air"
  xcrun metallib "$TMP/Fisheye.air" -o "$BUNDLE/default.metallib"
fi
APP="dist/Apollo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Apollo" "$APP/Contents/MacOS/Apollo"
cp -R "$BUNDLE" "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Demo.lrc "$APP/Contents/Resources/Demo.lrc"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
/usr/bin/codesign --force --sign "${SIGNING_IDENTITY:--}" --options runtime --entitlements Resources/Apollo.entitlements "$APP"
/usr/bin/codesign --verify --strict "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" dist/Apollo-macOS.zip
echo "Built $APP and dist/Apollo-macOS.zip"
