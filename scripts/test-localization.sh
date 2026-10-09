#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# 2026-09-11: Test the actual bundled resources after scripts/build.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -swift-version 5 Sources/Yinqi/Localization.swift Sources/Yinqi/Settings.swift Sources/Yinqi/SettingsStore.swift Tests/LocalizationTests.swift -o build/LocalizationTests
build/LocalizationTests
# Check resource coverage against source lookups, including dynamically displayed category keys.
python3 - <<'PY'
import re,json,subprocess,pathlib
path=pathlib.Path('Resources/zh-Hans.lproj/Localizable.strings')
base=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(path)]))
used=set()
for source in pathlib.Path('Sources/Yinqi').glob('*.swift'):
    for key in re.findall(r'L\("((?:\\.|[^"\\])*)"',source.read_text()):
        used.add(json.loads('"'+key+'"'))
assert not used-set(base),used-set(base)
print('PASS: all literal localization lookups have resources')
PY
# All preference changes in this test are volatile, and the disposable bundle has its own identifier.
localization_test_dir=$(mktemp -d)
trap 'rm -rf "$localization_test_dir"' EXIT
ditto build/Yinqi.app "$localization_test_dir/Yinqi.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.yinqi.localization-test' "$localization_test_dir/Yinqi.app/Contents/Info.plist"
xcrun swiftc -swift-version 5 Sources/Yinqi/Localization.swift Tests/NativeLocalizationTests.swift -o "$localization_test_dir/Yinqi.app/Contents/MacOS/Yinqi"
codesign --force --sign - "$localization_test_dir/Yinqi.app"
for locale in zh-Hans zh-HK zh-TW en fr de ja ko; do "$localization_test_dir/Yinqi.app/Contents/MacOS/Yinqi" "$locale"; done
