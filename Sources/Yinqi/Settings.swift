import Foundation
import CoreGraphics

/// Schema 1 stores appearance and logical-point geometry, never audio or permission state.
struct Settings: Codable, Equatable {
    var schemaVersion = 1
    /// 2026-09-11: Persist language choice; system is resolved at launch.
    var language = "system"
    /// 2026-09-11: Persist explicit backend choice; old settings keep the performance branch layer default.
    var rendererBackend = "coreAnimation"
    var advancedSettings = false
    // 2026-09-11: Additive defaults preserve existing appearance; zero FPS follows the display.
    var channelMode = "merged"
    var stereoOrder = "ascending"
    var channelGap = 0.0
    var frequencyMin = 20.0
    var frequencyMax = 20000.0
    var gradientDirection = "horizontal"
    var roundBase = false
    var layoutMode = "custom"
    var frameRate = 60
    var customFrameRate = false
    var lastLimitedFrameRate = 60
    static let frameRatePresets = [10, 15, 30, 60, 120]
    /// 2026-09-11: Opt in to screenshot exclusion using AppKit window sharing policy.
    var hideInScreenshots = false
    var showInDock = true
    var hasLaunched = false
    var spectrumEnabled = false
    var placementMode = "bottom"
    var x = 0.0
    var y = 0.0
    var width = 0.0
    var height = 96.0
    var screenHint = ""
    var edgeInset = 8.0
    var growthDirection = "up"
    var barCount = 64
    var style = "solid"
    var primaryColor = [0.2, 0.85, 1.0]
    var gradientColors = [[0.2, 0.85, 1.0], [0.9, 0.25, 0.65]]
    var barOpacity = 0.7
    var gap = 2.0
    var cornerRadius = 2.0
    var sensitivityDB = 0.0
    var releaseMs = 180.0
    var peakEnabled = false
    var peakStyle = "brick"
    var peakThickness = 3.0
    var peakFallSpeed = 30.0
    var peakCustomColor = false
    var peakColor = [1.0, 1.0, 1.0]

    /// Constrain external configuration before allocating arrays or applying window geometry.
    func validated() -> Settings {
        var s = self
        s.schemaVersion = 1
        if s.language != "system" && !AppLanguage.codes.contains(s.language) { s.language = "system" }
        if !["coreAnimation", "metal"].contains(s.rendererBackend) { s.rendererBackend = "coreAnimation" }
        if !["merged", "stereo"].contains(s.channelMode) { s.channelMode = "merged" }
        if !["ascending", "lowOutside", "lowInside"].contains(s.stereoOrder) { s.stereoOrder = "ascending" }
        if !["horizontal", "vertical"].contains(s.gradientDirection) { s.gradientDirection = "horizontal" }
        if !["custom", "fill"].contains(s.layoutMode) { s.layoutMode = "custom" }
        s.channelGap = bound(channelGap, 0, 40, 0)
        s.frequencyMin = bound(frequencyMin, 20, 19999, 20)
        s.frequencyMax = bound(frequencyMax, s.frequencyMin + 1, 20000, 20000)
        s.frameRate = s.frameRate == 0 ? 0 : min(1000, max(10, s.frameRate))
        // 2026-09-11: Preserve legacy nonpreset rates as custom, and remember finite rates across unlimited mode.
        s.lastLimitedFrameRate = min(1000, max(10, s.lastLimitedFrameRate))
        if s.frameRate != 0 { s.lastLimitedFrameRate = s.frameRate }
        if !Self.frameRatePresets.contains(s.lastLimitedFrameRate) { s.customFrameRate = true }
        if ![16,32,64,128].contains(s.barCount) { s.barCount = 64 }
        if !["top","bottom","left","right","free"].contains(s.placementMode) { s.placementMode = "bottom" }
        if !["up","down","left","right"].contains(s.growthDirection) { s.growthDirection = "up" }
        if !["solid","gradient","led"].contains(s.style) { s.style = "solid" }
        s.x = x.isFinite ? x : 0; s.y = y.isFinite ? y : 0
        // 2026-09-11: Side docking uses height as the long axis and width as amplitude thickness.
        s.width = s.isVertical ? bound(width, 24, 240, 96) : bound(width, 0, 20000, 0)
        s.height = s.isVertical ? bound(height, 0, 20000, 0) : bound(height, 24, 240, 96)
        s.edgeInset = bound(edgeInset, 0, 120, 8)
        s.gap = bound(gap, 0, 8, 2); s.cornerRadius = bound(cornerRadius, 0, 8, 2)
        s.barOpacity = bound(barOpacity, 0.1, 1, 0.7)
        s.sensitivityDB = bound(sensitivityDB, -24, 24, 0)
        s.releaseMs = bound(releaseMs, 80, 500, 180)
        // 2026-09-11: Normalize peak configuration before passing values to the shader.
        if !["line", "brick", "rounded"].contains(s.peakStyle) { s.peakStyle = "brick" }
        s.peakThickness = bound(peakThickness, 1, 12, 3)
        s.peakFallSpeed = bound(peakFallSpeed, 1, 200, 30)
        s.peakColor = normalizedColor(peakColor)
        s.primaryColor = normalizedColor(primaryColor)
        s.gradientColors = gradientColors.count == 2 ? gradientColors.map(normalizedColor) : Settings().gradientColors
        return s
    }

    /// 2026-09-11: Unlimited changes scheduling only and restores the last finite selection when disabled.
    func settingUnlimited(_ enabled: Bool) -> Settings {
        var s = validated()
        if enabled { s.frameRate = 0 } else { s.frameRate = s.lastLimitedFrameRate }
        return s.validated()
    }

    /// 2026-09-11: Leaving custom mode selects the closest preset; ties prefer the lower rate.
    func settingCustomFrameRate(_ enabled: Bool) -> Settings {
        var s = validated()
        s.customFrameRate = enabled
        if !enabled {
            let nearest = Self.frameRatePresets.min { abs($0-s.lastLimitedFrameRate) < abs($1-s.lastLimitedFrameRate) }!
            s.lastLimitedFrameRate = nearest
            if s.frameRate != 0 { s.frameRate = nearest }
        }
        return s.validated()
    }

    /// Growth determines the frequency axis even after a docked overlay is dragged free.
    var isVertical: Bool { growthDirection == "left" || growthDirection == "right" }

    /// 2026-09-11: Preserve strip length/thickness when turning a horizontal strip onto a side.
    func placing(at edge: String) -> Settings {
        var s = self
        let direction = ["bottom": "up", "top": "down", "left": "right", "right": "left"][edge]
        if let direction {
            let vertical = direction == "left" || direction == "right"
            if vertical != isVertical { swap(&s.width, &s.height) }
            s.growthDirection = direction
        }
        s.placementMode = edge
        return s.validated()
    }

    /// 2026-09-11: Centering detaches from the edge; docked restoration otherwise overrides x/y.
    func centered(in safe: CGRect, frame: CGRect) -> Settings {
        var s = self
        s.placementMode = "free"; s.layoutMode = "custom"
        s.width = frame.width; s.height = frame.height
        s.x = safe.midX-frame.width/2; s.y = safe.midY-frame.height/2
        return s.validated()
    }

    /// Merge missing schema fields with defaults; ignore future unknown keys.
    static func decode(_ data: Data) throws -> Settings {
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as! [String: Any]
        guard let supplied = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        let merged = defaults.merging(supplied) { _, new in new }
        return try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: merged)).validated()
    }
}

/// Reject NaN and infinity before applying any numeric setting.
func bound(_ value: Double, _ lower: Double, _ upper: Double, _ fallback: Double) -> Double {
    value.isFinite ? min(upper, max(lower, value)) : fallback
}

/// Accept exactly one RGB triplet and constrain all channels to the display range.
func normalizedColor(_ value: [Double]) -> [Double] {
    value.count == 3 ? value.map { bound($0, 0, 1, 0) } : [0.2,0.85,1]
}

/// Restore a single overlay into a supplied visible screen, including negative display coordinates.
func restoredFrame(_ settings: Settings, safe: CGRect) -> CGRect {
    let s = settings.validated()
    let longLimit = s.isVertical ? safe.height : safe.width
    let storedLength = s.isVertical ? s.height : s.width
    let length = s.layoutMode == "fill" ? longLimit : min(longLimit, max(min(240, longLimit), storedLength > 0 ? storedLength : longLimit * 0.7))
    let w = s.isVertical ? min(safe.width, s.width) : length
    let h = s.isVertical ? length : min(safe.height, s.height)
    let inset = min(s.edgeInset, max(0, ((s.isVertical ? safe.width : safe.height) - (s.isVertical ? w : h)) / 2))
    var x = s.placementMode == "free" ? s.x : safe.midX - w / 2
    var y = s.placementMode == "free" ? s.y : safe.midY - h / 2
    switch s.placementMode {
    case "bottom": y = safe.minY + inset
    case "top": y = safe.maxY - h - inset
    case "left": x = safe.minX + inset
    case "right": x = safe.maxX - w - inset
    default: break
    }
    return CGRect(x: min(max(x,safe.minX),safe.maxX-w), y: min(max(y,safe.minY),safe.maxY-h), width:w,height:h)
}

/// Parse complete localized numbers; reject partial, nonfinite and out-of-range input without overwriting a setting.
func parsedSettingNumber(_ text: String, range: ClosedRange<Double>, locale: Locale = .current) -> Double? {
    let separator = locale.decimalSeparator ?? "."
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: separator, with: ".")
    guard let value = Double(normalized), value.isFinite, range.contains(value) else { return nil }
    return value
}
