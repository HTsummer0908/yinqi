import AppKit
import QuartzCore

/// 2026-09-11: Layer-based performance backend; shared paths replace continuous app-owned Metal submissions.
final class LayerSpectrumRenderer: SpectrumRendering {
    let surfaceView = NSView(frame: .zero)
    private(set) var isPaused = true
    private(set) var drawCallbacks: UInt64 = 0
    private(set) var submittedFrames: UInt64 = 0
    private(set) var lastDrawFailure = "无"
    var frameProvider: (() -> SpectrumFrame?)?
    private var settings = Settings()
    private var frame = SpectrumFrame(bands: [], rmsDB: -160, timestamp: 0, sequence: 0, opacity: 0)
    private var hidden = true
    private var timer: Timer?
    private var rate = 0
    private var animation = SpectrumAnimation()
    private var peaks = PeakAnimation()
    private let bars = CAShapeLayer()
    private let caps = CAShapeLayer()
    private let barGradient = CAGradientLayer()
    private let capGradient = CAGradientLayer()
    private let stripes = CAShapeLayer()
    private var styledSize = CGSize.zero
    private var styledScale: CGFloat = 0
    private var styledSettings: Settings?

    /// 2026-09-11: Create a bounded layer tree once; paths and geometry are updated without implicit animations.
    init() {
        surfaceView.wantsLayer = true
        surfaceView.layer?.masksToBounds = true
        surfaceView.layer?.addSublayer(bars)
        surfaceView.layer?.addSublayer(caps)
    }
    deinit { timer?.invalidate() }

    /// 2026-09-11: Match Metal's wake/clear policy and invalidate animation when band identities change.
    func update(_ frame: SpectrumFrame, settings: Settings, editing: Bool, hidden: Bool) {
        if self.settings.channelMode != settings.channelMode || self.settings.barCount != settings.barCount ||
            self.settings.frequencyMin != settings.frequencyMin || self.settings.frequencyMax != settings.frequencyMax ||
            self.settings.stereoOrder != settings.stereoOrder || self.settings.growthDirection != settings.growthDirection ||
            self.settings.peakEnabled != settings.peakEnabled {
            animation = SpectrumAnimation(); peaks = PeakAnimation()
        }
        let needsRefresh = self.settings != settings || styledSize != surfaceView.bounds.size || isPaused
        self.settings = settings; self.frame = frame; self.hidden = hidden
        let maximum = max(10, surfaceView.window?.screen?.maximumFramesPerSecond ?? 60)
        let desired = settings.frameRate == 0 ? maximum : min(maximum, max(10, settings.frameRate))
        let pause = hidden || frame.opacity <= 0
        if pause {
            timer?.invalidate(); timer = nil; rate = 0; isPaused = true
            animation = SpectrumAnimation(); peaks = PeakAnimation()
            render()
        } else {
            isPaused = false
            if timer == nil || rate != desired {
                timer?.invalidate(); rate = desired
                let clock = Timer(timeInterval: 1/Double(desired), repeats: true) { [weak self] _ in self?.render() }
                clock.tolerance = 0.001
                RunLoop.main.add(clock, forMode: .common); timer = clock
            }
            if needsRefresh { render() }
        }
    }

    /// 2026-09-11: Reuse raw FFT targets, reject stale layouts, and submit only geometry/opacity transactions.
    private func render() {
        if !hidden, let current = frameProvider?() { frame = current }
        drawCallbacks &+= 1
        let size = surfaceView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        configureLayers(size: size)
        let mismatch = frame.bands.count != settings.barCount ||
            frame.channelMode.map { $0 != settings.channelMode } == true ||
            frame.frequencyMin.map { $0 != settings.frequencyMin } == true ||
            frame.frequencyMax.map { $0 != settings.frequencyMax } == true
        surfaceView.layer?.opacity = hidden || mismatch ? 0 : Float(frame.opacity)
        guard !hidden, !mismatch, frame.opacity > 0 else { return }
        let time = ProcessInfo.processInfo.systemUptime
        let values = frame.targetBands.map { animation.advance(target: $0, time: time, release: settings.releaseMs/1000) } ?? frame.bands
        let markers = settings.peakEnabled ? peaks.advance(bars: values, time: time, speed: settings.peakFallSpeed/100) : []
        let geometry = Self.paths(values: values, markers: markers, settings: settings, size: size)
        bars.path = geometry.0; caps.path = geometry.1
        submittedFrames &+= 1
    }

    /// 2026-09-11: Build style/mask layers only on configuration or size changes, keeping LED stripe geometry static.
    private func configureLayers(size: CGSize) {
        let scale = surfaceView.window?.backingScaleFactor ?? 2
        guard styledSize != size || styledSettings != settings || styledScale != scale else { return }
        styledSize = size; styledSettings = settings; styledScale = scale
        for layer in [bars, caps, stripes] { layer.contentsScale = scale; layer.frame = CGRect(origin: .zero, size: size) }
        bars.removeFromSuperlayer(); caps.removeFromSuperlayer()
        barGradient.removeFromSuperlayer(); capGradient.removeFromSuperlayer()
        barGradient.mask = nil; capGradient.mask = nil; bars.mask = nil
        let root = surfaceView.layer!
        let gradient = settings.style == "gradient"
        let first = Self.color(settings.primaryColor)
        bars.fillColor = gradient ? NSColor.white.cgColor : first
        caps.fillColor = settings.peakCustomColor ? Self.color(settings.peakColor) : (gradient ? NSColor.white.cgColor : first)
        for layer in [barGradient, capGradient] {
            layer.frame = CGRect(origin: .zero, size: size)
            layer.colors = settings.gradientColors.map(Self.color)
            layer.startPoint = .zero
            layer.endPoint = settings.gradientDirection == "vertical" ? CGPoint(x:0,y:1) : CGPoint(x:1,y:0)
        }
        if gradient {
            barGradient.mask = bars; barGradient.opacity = Float(settings.barOpacity); root.addSublayer(barGradient)
        } else { bars.opacity = Float(settings.barOpacity); root.addSublayer(bars) }
        // Masks need full opacity; alpha belongs on the visible shape or gradient, not both.
        if gradient { bars.opacity = 1 }
        if gradient && !settings.peakCustomColor {
            capGradient.mask = caps; caps.opacity = 1; capGradient.opacity = Float(settings.barOpacity); root.addSublayer(capGradient)
        } else { caps.opacity = Float(settings.barOpacity); root.addSublayer(caps) }
        caps.isHidden = !settings.peakEnabled; capGradient.isHidden = !settings.peakEnabled
        if settings.style == "led" {
            let path = CGMutablePath()
            let amplitude = settings.isVertical ? size.width : size.height
            let length = settings.isVertical ? size.height : size.width
            for y in stride(from: 1.3, to: amplitude, by: 6) {
                path.addRect(Self.oriented(CGRect(x:0,y:y,width:length,height:min(4.7,amplitude-y)), settings: settings, size: size))
            }
            stripes.path = path; stripes.fillColor = NSColor.white.cgColor; bars.mask = stripes
        }
    }

    /// 2026-09-11: Convert portable RGB values into the same sRGB endpoints used by the Metal backend.
    private static func color(_ rgb: [Double]) -> CGColor {
        NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1).cgColor
    }

    /// 2026-09-11: Map canonical bottom-up rectangles to all four growth directions; side bands run top to bottom.
    private static func oriented(_ rect: CGRect, settings: Settings, size: CGSize) -> CGRect {
        switch settings.growthDirection {
        case "down": return CGRect(x:rect.minX,y:size.height-rect.maxY,width:rect.width,height:rect.height)
        case "right": return CGRect(x:rect.minY,y:size.height-rect.maxX,width:rect.height,height:rect.width)
        case "left": return CGRect(x:size.width-rect.maxY,y:size.height-rect.maxX,width:rect.height,height:rect.width)
        default: return rect
        }
    }

    /// 2026-09-11: Build two compound paths with per-channel ordering, independent tip/base corners and peak styles.
    static func paths(values: [Float], markers: [Float], settings: Settings, size: CGSize) -> (CGPath, CGPath) {
        let body = CGMutablePath(), peak = CGMutablePath()
        guard !values.isEmpty else { return (body,peak) }
        let count = values.count, half = count/2
        let length = settings.isVertical ? size.height : size.width
        let amplitude = settings.isVertical ? size.width : size.height
        let separator = settings.channelMode == "stereo" ? min(settings.channelGap,max(0,length-Double(count))) : 0
        let gap = min(settings.gap,max(0,(length-separator-Double(count))/Double(max(1,count-1))))
        let width = max(0.1,(length-separator-gap*Double(count-1))/Double(count))
        var transform: CGAffineTransform
        switch settings.growthDirection {
        case "down": transform = CGAffineTransform(a:1,b:0,c:0,d:-1,tx:0,ty:size.height)
        case "right": transform = CGAffineTransform(a:0,b:-1,c:1,d:0,tx:0,ty:size.height)
        case "left": transform = CGAffineTransform(a:0,b:-1,c:-1,d:0,tx:size.width,ty:size.height)
        default: transform = .identity
        }
        for visual in 0..<count {
            var index = visual
            if settings.channelMode == "stereo", half > 0 {
                let right = visual >= half
                let reverse = settings.stereoOrder == "lowOutside" && right || settings.stereoOrder == "lowInside" && !right
                if reverse { index = (right ? half : 0)+half-1-visual%half }
            }
            let x = Double(visual)*(width+gap)+(visual>=half ? separator:0)
            let height = Double(min(1,max(0,values[index])))*amplitude
            if height >= 0.1 {
                let rect = CGRect(x:x,y:0,width:width,height:height)
                let radius = min(settings.cornerRadius,min(width,height)*0.5)
                let path = tipPath(rect, radius: radius, roundBase: settings.roundBase)
                body.addPath(path, transform: transform)
            }
            if settings.peakEnabled, markers.count == count {
                let h = Double(min(1,max(0,markers[index])))*amplitude
                if h > 0.1 {
                    let t = min(settings.peakStyle == "line" ? 1 : settings.peakThickness,amplitude)
                    let rect = CGRect(x:x,y:min(h,amplitude-t),width:width,height:t)
                    let r = settings.peakStyle == "rounded" ? min(width,t)*0.3 : 0
                    peak.addPath(CGPath(roundedRect: rect, cornerWidth:r,cornerHeight:r,transform:nil),transform:transform)
                }
            }
        }
        return (body,peak)
    }

    /// 2026-09-11: Round canonical top corners while keeping the baseline square unless explicitly requested.
    private static func tipPath(_ r: CGRect, radius: CGFloat, roundBase: Bool) -> CGPath {
        if roundBase { return CGPath(roundedRect:r,cornerWidth:radius,cornerHeight:radius,transform:nil) }
        let p = CGMutablePath()
        p.move(to:CGPoint(x:r.minX,y:r.minY));p.addLine(to:CGPoint(x:r.maxX,y:r.minY))
        p.addLine(to:CGPoint(x:r.maxX,y:r.maxY-radius))
        p.addArc(tangent1End:CGPoint(x:r.maxX,y:r.maxY),tangent2End:CGPoint(x:r.maxX-radius,y:r.maxY),radius:radius)
        p.addLine(to:CGPoint(x:r.minX+radius,y:r.maxY))
        p.addArc(tangent1End:CGPoint(x:r.minX,y:r.maxY),tangent2End:CGPoint(x:r.minX,y:r.maxY-radius),radius:radius)
        p.closeSubpath(); return p
    }
}
