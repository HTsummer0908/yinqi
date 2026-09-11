import MetalKit

/// Metal draws one transparent quad with analytic bars; no audio access or mutable DSP arrays.
final class SpectrumRenderer: NSObject, MTKViewDelegate {
    let view: MTKView
    private(set) var drawCallbacks: UInt64 = 0
    private(set) var submittedFrames: UInt64 = 0
    private(set) var lastDrawFailure = "尚未收到绘制回调"
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var frame = SpectrumFrame(bands: [], rmsDB: -160, timestamp: 0, sequence: 0, opacity: 0)
    private var settings = Settings()
    private var editing = false
    var frameProvider: (() -> SpectrumFrame?)?
    private var animation = SpectrumAnimation()
    private var animatedBands: [Float]?
    private var hidden = true

    /// Compile the embedded Metal source once, allowing a CLT-only build without metal CLI tools.
    init(frame initialFrame: CGRect = .zero) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "Yinqi.Metal", code: 1, userInfo: [NSLocalizedDescriptionKey:"Metal 设备不可用"])
        }
        self.queue = queue
        view = MTKView(frame: initialFrame, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0,0,0,0)
        view.layer?.isOpaque = false
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.preferredFramesPerSecond = 60
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name:"vertexMain")
        descriptor.fragmentFunction = library.makeFunction(name:"fragmentMain")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor:descriptor)
        super.init()
        view.delegate = self
    }

    /// Publish immutable UI-side render inputs and perform a final clear before pausing.
    func update(_ frame: SpectrumFrame, settings: Settings, editing: Bool, hidden: Bool) {
        let wasPaused = view.isPaused
        // 2026-09-11: Reset animation when the meaning of each bar changes; never blend channels.
        if self.settings.channelMode != settings.channelMode || self.settings.barCount != settings.barCount ||
            self.settings.frequencyMin != settings.frequencyMin || self.settings.frequencyMax != settings.frequencyMax {
            animation = SpectrumAnimation()
        }
        self.hidden = hidden
        animatedBands = nil
        self.frame = compatibleFrame(frame, settings: settings)
        if hidden { self.frame.opacity = 0 }
        self.settings = settings; self.editing = editing
        let maximum = max(10, view.window?.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 60)
        let rate = settings.frameRate == 0 ? maximum : min(maximum, max(10, settings.frameRate))
        if view.preferredFramesPerSecond != rate { view.preferredFramesPerSecond = rate }
        let paused = hidden || self.frame.opacity <= 0
        if paused { animation = SpectrumAnimation() }
        view.isPaused = paused
        if paused && !wasPaused { view.draw() }
        if editing && paused && !hidden { view.draw() }
    }

    /// 2026-09-11: The asynchronous DSP may still publish the previous layout for one callback.
    private func compatibleFrame(_ candidate: SpectrumFrame, settings: Settings) -> SpectrumFrame {
        guard candidate.channelMode.map({ $0 != settings.channelMode }) == true ||
                candidate.frequencyMin.map({ $0 != settings.frequencyMin }) == true ||
                candidate.frequencyMax.map({ $0 != settings.frequencyMax }) == true ||
                (!candidate.bands.isEmpty && candidate.bands.count != settings.barCount) else { return candidate }
        var cleared = candidate
        cleared.bands = []; cleared.targetBands = []; cleared.opacity = 0
        return cleared
    }

    /// Keep drawable pixels in sync with logical points when crossing Retina displays.
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// Render command buffers refer only to copied fragment bytes owned by this command encoder.
    func draw(in view: MTKView) {
        // 2026-09-11: Read targets on the draw clock instead of repeating a separate UI timer snapshot.
        if !hidden, let latest = frameProvider?() { frame = compatibleFrame(latest, settings: settings) }
        if let target = frame.targetBands {
            animatedBands = animation.advance(target: target, time: ProcessInfo.processInfo.systemUptime, release: settings.releaseMs / 1000)
        } else { animatedBands = nil }
        drawCallbacks &+= 1
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor:pass) else {
            lastDrawFailure = "未取得 drawable / render pass / command encoder"; return
        }
        lastDrawFailure = "无"
        submittedFrames &+= 1
        encodeBars(using: encoder, size: view.bounds.size)
        encoder.endEncoding(); command.present(drawable)
        command.addCompletedHandler { [weak self] completed in
            if let error = completed.error {
                DispatchQueue.main.async { self?.lastDrawFailure = "GPU 执行失败：\(error.localizedDescription)" }
            }
        }
        command.commit()
    }

    /// Encode the same production shader into a supplied render target for pixel-level verification.
    func encodeBars(using encoder: MTLRenderCommandEncoder, size: CGSize) {
        if !frame.bands.isEmpty && frame.opacity > 0 {
            let bars = animatedBands ?? frame.bands
            let count = bars.count
            let stereo = settings.channelMode == "stereo"
            let length = settings.isVertical ? size.height : size.width
            let centerGap = stereo ? min(settings.channelGap, max(0, length-Double(count))) : 0
            let gap = min(settings.gap,max(0,(length-centerGap-Double(count))/Double(max(1,count-1))))
            let first = settings.style == "gradient" ? settings.gradientColors[0] : settings.primaryColor
            let last = settings.gradientColors[1]
            var uniforms = [
                SIMD4<Float>(Float(size.width),Float(size.height),Float(count),Float(gap)),
                SIMD4<Float>(Float(settings.barOpacity),Float(settings.backgroundOpacity),Float(settings.cornerRadius),settings.growthDirection == "down" ? 1:0),
                SIMD4<Float>(settings.style == "gradient" ? 1 : (settings.style == "led" ? 2:0),Float(frame.opacity),Float(centerGap),stereo ? 1:0),
                SIMD4<Float>(Float(first[0]),Float(first[1]),Float(first[2]),1),
                SIMD4<Float>(Float(last[0]),Float(last[1]),Float(last[2]),1),
                SIMD4<Float>(settings.stereoOrder == "lowOutside" ? 1 : (settings.stereoOrder == "lowInside" ? 2 : 0),
                             settings.gradientDirection == "vertical" ? 1 : 0, settings.roundBase ? 1 : 0,
                             ["up": Float(0), "down": 1, "right": 2, "left": 3][settings.growthDirection] ?? 0)
            ]
            encoder.setRenderPipelineState(pipeline)
            bars.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!,length:$0.count,index:0) }
            uniforms.withUnsafeMutableBytes { encoder.setFragmentBytes($0.baseAddress!,length:$0.count,index:1) }
            encoder.drawPrimitives(type:.triangleStrip,vertexStart:0,vertexCount:4)
        }
    }

    /// Premultiplied alpha keeps a transparent window free of dark edge fringes.
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Out { float4 position [[position]]; float2 uv; };
    struct Uniforms { float4 layout; float4 options; float4 style; float4 first; float4 last; float4 extra; };
    vertex Out vertexMain(uint id [[vertex_id]]) {
        float2 p[4]={float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};
        Out o; o.position=float4(p[id],0,1); o.uv=(p[id]+1)*0.5; return o;
    }
    // 2026-09-11: Reorder only within each channel; left/right channel identity never changes.
    int dataIndex(int visual, int count, constant Uniforms &u) {
        if(u.style.w<0.5) return visual;
        int halfCount=count/2, local=visual%halfCount;
        bool right=visual>=halfCount;
        bool reverse=(u.extra.x>0.5 && u.extra.x<1.5 && right) || (u.extra.x>1.5 && !right);
        return (right?halfCount:0)+(reverse?halfCount-1-local:local);
    }
    // 2026-09-11: Round the tip independently of the baseline; side docking rotates both axes.
    float barMask(int index, float x, float y, float axisLength, float amplitude,
                  constant float *bands, constant Uniforms &u) {
        int count=int(u.layout.z);
        if(index<0 || index>=count) return 0;
        float gap=u.layout.w, separator=u.style.z;
        float barWidth=max(0.1,(axisLength-separator-gap*(count-1))/count);
        float origin=index*(barWidth+gap)+(index>=count/2?separator:0);
        float h=clamp(bands[dataIndex(index,count,u)],0.0,1.0)*amplitude;
        if(h<0.1) return 0;
        float radius=min(u.options.z,min(barWidth,h)*0.5);
        if(u.extra.z<0.5 && y<h*0.5) radius=0;
        float2 halfSize=float2(barWidth,h)*0.5;
        float2 q=abs(float2(x-origin,y)-halfSize)-halfSize+radius;
        float distance=length(max(q,0.0))+min(max(q.x,q.y),0.0)-radius;
        return 1-smoothstep(-0.5,0.5,distance);
    }
    fragment float4 fragmentMain(Out in [[stage_in]], constant float *bands [[buffer(0)]], constant Uniforms &u [[buffer(1)]]) {
        bool vertical=u.extra.w>1.5;
        float axisLength=vertical?u.layout.y:u.layout.x, amplitude=vertical?u.layout.x:u.layout.y;
        float x=(vertical?1-in.uv.y:in.uv.x)*axisLength;
        float y=(u.extra.w>2.5?1-in.uv.x:(vertical?in.uv.x:(u.extra.w>0.5?1-in.uv.y:in.uv.y)))*amplitude;
        float count=u.layout.z, gap=u.layout.w, separator=u.style.z;
        float width=max(0.1,(axisLength-separator-gap*(count-1))/count), pitch=width+gap;
        float split=(axisLength-separator)*0.5;
        float adjusted=x-(x>=split?separator:0);
        int index=clamp(int(adjusted/pitch),0,int(count)-1);
        float mask=barMask(index,x,y,axisLength,amplitude,bands,u);
        // 2026-09-11: Adjacent half-coverage edges must add to full coverage at zero spacing.
        if(gap<0.0001) mask=min(1.0,mask+barMask(index-1,x,y,axisLength,amplitude,bands,u)+barMask(index+1,x,y,axisLength,amplitude,bands,u));
        if(u.style.x>1.5) mask*=step(1.3,fmod(y,6.0));
        float factor=u.extra.y>0.5?in.uv.y:in.uv.x;
        float3 color=u.style.x>0.5 && u.style.x<1.5?mix(u.first.rgb,u.last.rgb,factor):u.first.rgb;
        float alpha=mask*u.options.x;
        float background=u.options.y*(1-alpha);
        return float4(color*alpha+(float3(0.03)*background),alpha+background)*u.style.y;
    }
    """
}


/// Draw-time exponential smoothing gives equal elapsed-time motion across different refresh rates.
struct SpectrumAnimation {
    private(set) var bands = [Float]()
    private var lastTime: Double?

    /// Advance towards raw FFT targets; never interpolate between incompatible bar layouts.
    mutating func advance(target: [Float], time: Double, release: Double) -> [Float] {
        if bands.count != target.count { bands = [Float](repeating: 0, count: target.count); lastTime = nil }
        let dt = lastTime.map { max(0, time - $0) } ?? 0
        lastTime = time
        for i in target.indices {
            bands[i] = smooth(bands[i], target: target[i], dt: dt, tau: target[i] > bands[i] ? 0.03 : release)
        }
        return bands
    }
}
