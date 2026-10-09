# Yinqi development guide

[English](DEVELOPMENT.en.md) | [中文](DEVELOPMENT.md) | [Back to the product page](../README.en.md)

This document collects source-build, project structure, localization, configuration, testing, and compatibility details. See the repository README for the product overview and downloads.

## Development environment

- Deployment target: macOS 26.0 or later
- Architecture: Apple Silicon (arm64)
- Verified hardware and OS: Apple M4, macOS 27.0 Beta (26A428)
- Toolchain: Swift 6.4, Swift 5 language mode, Xcode 27 Beta, and Icon Composer 2

A complete Xcode installation is required to compile the native layered icon. Other operating systems, Intel Macs, and toolchain versions have not been tested.

## Build

```sh
bash scripts/test.sh
bash scripts/build.sh
open build/Yinqi.app
```

The output is `build/Yinqi.app`. The build script checks common Xcode locations, or you can select one explicitly:

```sh
ICON_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" bash scripts/build.sh
```

Yinqi has no third-party runtime dependencies or SwiftPM downloads. It primarily uses Core Audio, Accelerate, AppKit, SwiftUI, MetalKit, and a C11 atomic queue.

## Source layout

- `Sources/Realtime`: the real-time single-producer/single-consumer audio queue.
- `Sources/Yinqi`: system-audio capture, spectrum analysis, rendering, settings, and UI.
- `Resources`: Info.plist, localization resources, and brand assets.
- `Tests`: queue, DSP, settings, localization, rendering, and termination checks.
- `scripts`: build and test entry points.

Screenshot exclusion uses the AppKit window-sharing property and references the public approach used by [LyricsX](https://github.com/MxIris-LyricsX-Project/LyricsX).

## Settings and lifecycle

Settings are stored at `~/Library/Application Support/local.xinfei.yinqi/settings.json`. Older configurations are migrated automatically without deleting the old file or overwriting an existing current file.

Exported JSON contains a format version and portable settings. It omits the display identifier, launch history, and spectrum enabled state. Invalid imports and failed saves leave the current settings unchanged. Language and renderer changes require a restart.

The menu bar is the primary entry point, with optional Dock visibility. Diagnostics run only when the user opens the diagnostics window. Closing Settings does not quit the app.

## Rendering and performance

Core Animation is the default renderer; Metal can be selected in Settings. Renderer changes use the Restart Now / Restart Later flow to avoid leaving resources from an in-process hot switch.

Frame-rate options include 10/15/30/60/120 presets, a custom 10–1000 range, or the display's highest refresh rate. Actual delivery remains subject to display capabilities and macOS scheduling. The spectrum fades and suspends continuous drawing after silence.

See [`docs/performance`](performance) for measurements and optimization history. Standalone probes do not represent every long-running playback workload in the complete app.

## Localization

Supported resource codes are `zh-Hans`, `zh-HK`, `zh-TW`, `en`, `fr`, `de`, `ja`, and `ko`. System Default selects the first supported macOS language and falls back to English.

- UI strings: `Resources/<language>.lproj/Localizable.strings`
- Localized name and permission text: `InfoPlist.strings` in the same directory
- Language registration: `AppLanguage.codes` and `CFBundleLocalizations`

Keep `%@` placeholders intact and run `bash scripts/test-localization.sh` after translation changes.

## Testing

Core checks:

```sh
bash scripts/test.sh
```

Native-window and pixel tests require a graphical session and briefly display test windows:

```sh
bash scripts/test-rendering.sh
bash scripts/test-localization.sh
bash scripts/test-termination.sh
```

See [`docs/testing`](testing) for historical results. Static and synthetic tests do not replace validation across every OS version, display, and long-running playback scenario.

## Privacy and distribution boundaries

System audio is analyzed locally in real time and is never recorded, stored, or uploaded. Yinqi does not send telemetry or automatically check for updates. Network access occurs only when a user opens a project link.

The current package is ad-hoc signed, not Developer ID signed, and not notarized by Apple. SHA-256 confirms file integrity but does not replace developer signing. Screenshot exclusion has been confirmed in the current environment but is not guaranteed for every screen recorder.

Yinqi is licensed under the [Mozilla Public License 2.0](../LICENSE). Any summary is subordinate to the license text.

## Release references

- Current release notes: [`docs/releases/1.1.1.md`](releases/1.1.1.md)
- Historical release notes: [`docs/releases`](releases)
- Theme preset design: [`docs/design/settings-presets.md`](design/settings-presets.md)
- Architecture record: [`2026-09-11-macos-spectrum-functional-architecture.md`](../2026-09-11-macos-spectrum-functional-architecture.md)
