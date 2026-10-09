#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Build a self-contained local app using the selected Apple command-line SDK.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/Yinqi.app/Contents/MacOS
xcrun clang -std=c11 -O2 -mmacosx-version-min=26.0 -I Sources/Realtime/include -c Sources/Realtime/Realtime.c -o build/Realtime.o
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx26.0 -I Sources/Realtime/include Sources/Yinqi/*.swift build/Realtime.o -framework AppKit -framework CoreAudio -o build/Yinqi.app/Contents/MacOS/Yinqi
# 2026-09-11: Package the approved icon and template PDF before signing.
mkdir -p build/Yinqi.app/Contents/Resources
# 2026-09-11: Compile the native layered icon with a full Xcode toolchain.
# ICON_DEVELOPER_DIR selects only the resource compiler, preserving the app compiler selection.
icon_developer_dir="${ICON_DEVELOPER_DIR:-${DEVELOPER_DIR:-$(xcode-select -p)}}"
if ! DEVELOPER_DIR="$icon_developer_dir" xcrun --find actool >/dev/null 2>&1; then
    # 2026-10-09: Search standard installations only; custom volumes use ICON_DEVELOPER_DIR.
    for candidate in /Applications/Xcode.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer; do
        if [ -x "$candidate/usr/bin/actool" ]; then icon_developer_dir="$candidate"; break; fi
    done
fi
DEVELOPER_DIR="$icon_developer_dir" xcrun actool Resources/Branding/v2/Yinqi.icon \
    --compile build/Yinqi.app/Contents/Resources --platform macosx \
    --minimum-deployment-target 26.0 --app-icon Yinqi \
    --output-partial-info-plist build/icon-info.plist
cp Resources/Branding/v2/menu/YinqiMenuTemplate.pdf build/Yinqi.app/Contents/Resources/
# 2026-09-11: Include UI and localized app-name/permission resources in the signed bundle.
for locale in Resources/*.lproj; do ditto "$locale" "build/Yinqi.app/Contents/Resources/$(basename "$locale")"; done
cp Resources/Info.plist build/Yinqi.app/Contents/Info.plist
# Merge generated icon metadata rather than maintaining compiler output keys manually.
/usr/libexec/PlistBuddy -c "Merge build/icon-info.plist" build/Yinqi.app/Contents/Info.plist
codesign --force --sign - build/Yinqi.app
codesign --verify --strict build/Yinqi.app
printf 'Built %s/build/Yinqi.app\n' "$PWD"
