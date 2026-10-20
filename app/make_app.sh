#!/bin/sh
# Build TouchMac.app (release) with the root helper bundled next to the app binary.
set -e
cd "$(dirname "$0")"

# Command Line Tools 27 ship an SDK where SwiftUI's @State is a macro, but not the
# macro plugin, so the app target fails to compile. Fall back to the 26 SDK they also ship.
DEV=$(xcode-select -p)
if [ -z "$SDKROOT" ] && [ -d "$DEV/SDKs" ] && ! ls "$DEV"/usr/lib/swift/host/plugins/*SwiftUIMacros* >/dev/null 2>&1; then
  for sdk in "$DEV"/SDKs/MacOSX26*.sdk; do [ -d "$sdk" ] && SDKROOT="$sdk"; done
  [ -n "$SDKROOT" ] && export SDKROOT && echo "using $SDKROOT (CLT has no SwiftUI macro plugin)"
fi

swift build -c release
APP=build/TouchMac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TouchMac .build/release/touchmacd "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp AppIcon.icns "$APP/Contents/Resources/"
codesign --force -s - "$APP/Contents/MacOS/touchmacd"
codesign --force -s - "$APP"
codesign --verify --strict "$APP"
echo "built: $(pwd)/$APP"
