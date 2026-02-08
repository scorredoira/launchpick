#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building release..."
swift build -c release 2>&1

echo "Stopping Launchpick..."
pkill -x Launchpick 2>/dev/null || true
sleep 1

echo "Installing to /Applications..."
# Create bundle if missing
APP_DIR="/Applications/Launchpick.app/Contents"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"
cp -f .build/release/Launchpick "$APP_DIR/MacOS/"
cp -f Info.plist "$APP_DIR/"
cp -f AppIcon.icns "$APP_DIR/Resources/" 2>/dev/null || true

echo "Signing..."
codesign --force --deep --sign - /Applications/Launchpick.app 2>&1

echo "Resetting Accessibility permission (needs re-grant)..."
tccutil reset Accessibility com.custom.launchpick 2>/dev/null || true

echo "Launching..."
open /Applications/Launchpick.app

echo ""
echo "Done! Grant Accessibility permission when prompted."
echo "Option+Tab will start working automatically after you grant it."
