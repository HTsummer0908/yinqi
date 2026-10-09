#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

"""Keep release metadata synchronized across the app, READMEs, and release notes."""

import plistlib
from pathlib import Path


version = "1.1.1"
build = "34"
info = plistlib.loads(Path("Resources/Info.plist").read_bytes())

assert info["CFBundleShortVersionString"] == version
assert info["CFBundleVersion"] == build

for readme_path in (Path("README.md"), Path("README.en.md")):
    readme = readme_path.read_text(encoding="utf-8")
    assert f"{version}" in readme
    assert f"build {build}" in readme.lower()

release_notes = Path(f"docs/releases/{version}.md")
assert release_notes.is_file()
notes = release_notes.read_text(encoding="utf-8")
assert f"{version}" in notes
assert build in notes and ("构建" in notes or "build" in notes.lower())

print(f"PASS: release metadata {version} build {build}")
