#!/bin/bash
# Run native layout/composition and actual Metal pixel tests without system audio capture.
# The layout test briefly displays an independent synthetic test window, not live spectrum evidence.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 Sources/Yinqi/Localization.swift Sources/Yinqi/Settings.swift Sources/Yinqi/SpectrumAnalyzer.swift Sources/Yinqi/SpectrumRenderer.swift Sources/Yinqi/LayerSpectrumRenderer.swift Sources/Yinqi/OverlayWindowController.swift Tests/OverlayLayoutTests.swift -framework AppKit -framework MetalKit -framework Accelerate -o build/OverlayLayoutTests
build/OverlayLayoutTests
xcrun swiftc -swift-version 5 Sources/Yinqi/Localization.swift Sources/Yinqi/Settings.swift Sources/Yinqi/SpectrumAnalyzer.swift Sources/Yinqi/SpectrumRenderer.swift Sources/Yinqi/LayerSpectrumRenderer.swift Tests/MetalPixelTests.swift -framework AppKit -framework MetalKit -framework Accelerate -o build/MetalPixelTests
build/MetalPixelTests

xcrun swiftc -swift-version 5 Sources/Yinqi/Localization.swift Sources/Yinqi/Settings.swift Sources/Yinqi/SpectrumAnalyzer.swift Sources/Yinqi/SpectrumRenderer.swift Sources/Yinqi/LayerSpectrumRenderer.swift Tests/AppearanceTests.swift -framework AppKit -framework MetalKit -framework Accelerate -o build/AppearanceTests
build/AppearanceTests

# 2026-09-11: Exercise layer backend output and lifecycle with assertions enabled.
xcrun swiftc -swift-version 5 Sources/Yinqi/Localization.swift Sources/Yinqi/Settings.swift Sources/Yinqi/SpectrumAnalyzer.swift Sources/Yinqi/SpectrumRenderer.swift Sources/Yinqi/LayerSpectrumRenderer.swift Tests/LayerRendererTests.swift -framework AppKit -framework MetalKit -framework Accelerate -o build/LayerRendererTests
build/LayerRendererTests
