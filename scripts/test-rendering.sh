#!/bin/bash
# Run native layout/composition and actual Metal pixel tests without system audio capture.
# The layout test briefly displays an independent synthetic test window, not live spectrum evidence.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 Sources/Soundbar/Settings.swift Sources/Soundbar/SpectrumAnalyzer.swift Sources/Soundbar/SpectrumRenderer.swift Sources/Soundbar/OverlayWindowController.swift Tests/OverlayLayoutTests.swift -framework AppKit -framework MetalKit -framework Accelerate -o build/OverlayLayoutTests
build/OverlayLayoutTests
xcrun swiftc -swift-version 5 Sources/Soundbar/Settings.swift Sources/Soundbar/SpectrumAnalyzer.swift Sources/Soundbar/SpectrumRenderer.swift Tests/MetalPixelTests.swift -framework AppKit -framework MetalKit -framework Accelerate -o build/MetalPixelTests
build/MetalPixelTests

xcrun swiftc -swift-version 5 Sources/Soundbar/Settings.swift Sources/Soundbar/SpectrumAnalyzer.swift Sources/Soundbar/SpectrumRenderer.swift Tests/AppearanceTests.swift -framework AppKit -framework MetalKit -framework Accelerate -o build/AppearanceTests
build/AppearanceTests
