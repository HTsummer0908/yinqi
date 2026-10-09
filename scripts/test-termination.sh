#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# 2026-09-11: Verify actual audio-stop callbacks can finish AppKit termination, including main-dispatch entry.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -std=c11 -O2 -mmacosx-version-min=26.0 -I Sources/Realtime/include -c Sources/Realtime/Realtime.c -o build/TerminationRealtime.o
xcrun swiftc -swift-version 5 -I Sources/Realtime/include Sources/Yinqi/Localization.swift Sources/Yinqi/Settings.swift Sources/Yinqi/SpectrumAnalyzer.swift Sources/Yinqi/AudioCaptureService.swift Sources/Yinqi/ApplicationRelauncher.swift Tests/TerminationTests.swift build/TerminationRealtime.o -framework AppKit -framework CoreAudio -o build/TerminationTests
python3 - <<'PY'
import subprocess, pathlib, tempfile, plistlib, shutil, time
for mode in ['dispatch', 'event']:
    process = subprocess.Popen(['build/TerminationTests', mode], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        output, _ = process.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        output, _ = process.communicate()
        raise AssertionError(f'{mode}: AppKit termination timed out: {output}')
    assert process.returncode == 0 and 'PASS:' in output, (mode, process.returncode, output)
    print(mode, output.strip())
# Exercise production relaunch helper + production stop completion without touching real app settings.
with tempfile.TemporaryDirectory(prefix='yinqi restart ') as directory:
    root = pathlib.Path(directory)
    app = root / 'Yinqi test $quote.app'
    executable = app / 'Contents/MacOS/Yinqi'
    executable.parent.mkdir(parents=True)
    shutil.copy('build/TerminationTests', executable)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier':'local.yinqi.termination-test', 'CFBundleName':'Yinqi Termination Test',
        'CFBundleExecutable':'Yinqi', 'CFBundlePackageType':'APPL', 'LSUIElement':True}))
    subprocess.run(['codesign','--force','--sign','-',str(app)],check=True,capture_output=True)
    process = subprocess.Popen([str(executable), 'relaunch'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    try:
        output, _ = process.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill(); process.communicate()
        raise AssertionError('Original app failed to exit during relaunch')
    assert process.returncode == 0, output
    record = root / 'termination-pids.txt'
    pids = []
    for _ in range(100):
        pids = record.read_text().splitlines() if record.exists() else []
        if len(pids) == 2: break
        time.sleep(0.1)
    assert len(pids) == 2 and pids[0] == str(process.pid) and pids[0] != pids[1], pids
    print('PASS: full AppKit quit and automatic relaunch, old/new PID', *pids)
PY
