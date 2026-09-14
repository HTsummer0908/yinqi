#!/usr/bin/env python3
"""Validate the public identity and project links rendered by the About section."""

from pathlib import Path


source = Path("Sources/Yinqi/SettingsView.swift").read_text(encoding="utf-8")

# The About card credits development without implying a runtime GPT dependency.
assert 'Text("Developed by HTsummer")' in source
assert 'Text("Built with GPT-6 Astra")' in source
assert 'LabeledContent(L("开发者")' not in source
assert 'Link(L("开发者 GitHub")' not in source

# Keep only the project repository link and show the current source license.
assert source.count('Link(L("项目 GitHub")') == 1
assert 'L("本项目采用 Mozilla Public License 2.0。")' in source
assert 'L("开源许可证待确定；正式发布信息以项目 README 为准。")' not in source

print("PASS: About attribution, repository link and license status")
