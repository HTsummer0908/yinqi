#!/bin/bash
# Build a self-contained local app using the selected Apple command-line SDK.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/Soundbar.app/Contents/MacOS
xcrun clang -std=c11 -O2 -mmacosx-version-min=26.0 -I Sources/Realtime/include -c Sources/Realtime/Realtime.c -o build/Realtime.o
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx26.0 -I Sources/Realtime/include Sources/Soundbar/*.swift build/Realtime.o -framework AppKit -framework CoreAudio -o build/Soundbar.app/Contents/MacOS/Soundbar
# 2026-09-11: Package the approved icon and template PDF before signing.
mkdir -p build/Soundbar.app/Contents/Resources
# 2026-09-11: Compile the native layered icon with a full Xcode toolchain.
# ICON_DEVELOPER_DIR selects only the resource compiler, preserving the app compiler selection.
icon_developer_dir="${ICON_DEVELOPER_DIR:-${DEVELOPER_DIR:-$(xcode-select -p)}}"
if ! DEVELOPER_DIR="$icon_developer_dir" xcrun --find actool >/dev/null 2>&1; then
    for candidate in /Applications/Xcode.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer /Volumes/Data/Applications/Xcode-beta.app/Contents/Developer; do
        if [ -x "$candidate/usr/bin/actool" ]; then icon_developer_dir="$candidate"; break; fi
    done
fi
DEVELOPER_DIR="$icon_developer_dir" xcrun actool Resources/Branding/v2/Yinqi.icon \
    --compile build/Soundbar.app/Contents/Resources --platform macosx \
    --minimum-deployment-target 26.0 --app-icon Yinqi \
    --output-partial-info-plist build/icon-info.plist
cp Resources/Branding/v2/menu/YinqiMenuTemplate.pdf build/Soundbar.app/Contents/Resources/
cp Resources/Info.plist build/Soundbar.app/Contents/Info.plist
# Merge generated icon metadata rather than maintaining compiler output keys manually.
/usr/libexec/PlistBuddy -c "Merge build/icon-info.plist" build/Soundbar.app/Contents/Info.plist
codesign --force --sign - build/Soundbar.app
codesign --verify --strict build/Soundbar.app
printf 'Built %s/build/Soundbar.app\n' "$PWD"
