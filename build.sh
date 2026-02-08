#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building Launchpick..."
swift build -c release 2>&1

echo ""
echo "Creating app bundle..."
APP_DIR="build/Launchpick.app/Contents"
rm -rf build/Launchpick.app
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

cp .build/release/Launchpick "$APP_DIR/MacOS/"
cp Info.plist "$APP_DIR/"
cp AppIcon.icns "$APP_DIR/Resources/"

echo "Signing..."
codesign --force --sign - build/Launchpick.app 2>&1

echo ""
echo "Done! App is at build/Launchpick.app"
echo ""
echo "To run:     open build/Launchpick.app"
echo "To install: cp -r build/Launchpick.app /Applications/"
