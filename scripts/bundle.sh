#!/bin/sh
# Builds dist/manotify.app. Pass an output directory to build elsewhere.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-"$root/dist"}
app="$out/manotify.app"

cd "$root"
swift build -c release --disable-sandbox
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/manotify" "$app/Contents/MacOS/manotify"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
# The build sandbox may block this; manotify registers itself on first run anyway.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" || true
echo "$app"
