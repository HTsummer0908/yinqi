#!/bin/bash
# Verify the realtime transport without starting audio capture or requesting permission.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -std=c11 -Wall -Wextra -Wno-unused-parameter -fsanitize=address,undefined -I Sources/Realtime/include Tests/RealtimeTests.c Sources/Realtime/Realtime.c -o build/RealtimeTests
build/RealtimeTests
xcrun swiftc -swift-version 5 Sources/Yinqi/Localization.swift Sources/Yinqi/Settings.swift Sources/Yinqi/SpectrumAnalyzer.swift Tests/DSPTests.swift Tests/AnalyzerFixture.swift -framework Accelerate -o build/DSPTests
build/DSPTests
xcrun swiftc -swift-version 5 Sources/Yinqi/Localization.swift Sources/Yinqi/Settings.swift Sources/Yinqi/SettingsStore.swift Tests/SettingsTests.swift -o build/SettingsTests
build/SettingsTests
# 2026-09-14: Guard the About card attribution, repository link, and confirmed license status.
python3 Tests/AboutSectionTests.py
xcrun clang -std=c11 -Wall -Wextra -Wno-unused-parameter -fsanitize=thread -I Sources/Realtime/include Tests/RealtimeConcurrencyTests.c Sources/Realtime/Realtime.c -o build/RealtimeConcurrencyTests
build/RealtimeConcurrencyTests
