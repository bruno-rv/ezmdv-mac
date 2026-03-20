#!/usr/bin/env bash
# Build ezmdv native macOS app and create .dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="ezmdv"
BUNDLE_ID="com.ezmdv.native"
VERSION="1.0.0"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/${APP_NAME}.app"
DMG_DIR="$ROOT/dist"

echo "==> Building editor bundle..."
if [ -f "$ROOT/resources/package.json" ]; then
  (cd "$ROOT/resources" && npm run build)
fi

echo "==> Building ${APP_NAME} (release)..."
swift build -c release

echo "==> Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/EzmdvApp" "$APP_DIR/Contents/MacOS/${APP_NAME}"

# Copy resources
if [ -d "$BUILD_DIR/EzmdvApp_EzmdvApp.bundle" ]; then
  cp -R "$BUILD_DIR/EzmdvApp_EzmdvApp.bundle" "$APP_DIR/Contents/Resources/"
fi

# Copy app icon
if [ -f "$ROOT/assets/AppIcon.icns" ]; then
  cp "$ROOT/assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> App bundle created at: $APP_DIR"

# Create DMG
echo "==> Creating DMG..."
DMG_PATH="$DMG_DIR/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG_PATH"

# Create a temporary folder for DMG contents
DMG_TMP="$DMG_DIR/dmg-tmp"
rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"
cp -R "$APP_DIR" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TMP" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_TMP"

echo ""
echo "=== Done! ==="
echo "App:  $APP_DIR"
echo "DMG:  $DMG_PATH"
echo ""
echo "To run:  open \"$APP_DIR\""
echo "To share: send the .dmg file"
