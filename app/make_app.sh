#!/bin/sh
# Build TouchMac.app (release) with the root helper bundled next to the app binary.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/TouchMac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TouchMac "$APP/Contents/MacOS/"
cp .build/release/touchmacd "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force -s - "$APP"
echo "built: $(pwd)/$APP"
