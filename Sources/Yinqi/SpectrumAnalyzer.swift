import Foundation
import Accelerate

/// An immutable latest-only snapshot; sequence and monotonic time identify stale frames.
struct SpectrumFrame {
    var bands: [Float]
    var rmsDB: Double
    var timestamp: Double
    var sequence: UInt64
    var opacity: Double = 1
    var targetBands: [Float]? = nil
    var channelMode: String? = nil
    var frequencyMin: Double? = nil
    var frequencyMax: Double? = nil
}

/// Small lock is used only by DSP/UI, never the realtime audio callback.
final class SpectrumFrameStore {
    private let lock = NSLock()
    private var frame = SpectrumFrame(bands: [Float](repeating:0,count:64), rmsDB:-160,timestamp:0,sequence:0,opacity:0)
    /// Replace rather than enqueue analysis results, bounding UI latency.
    func publish(_ value: SpectrumFrame) { lock.lock(); frame = value; lock.unlock() }
    /// Return a Swift value snapshot protected against concurrent publication.
    func snapshot() -> SpectrumFrame { lock.lock(); defer {lock.unlock()}; return frame }
}

/// Exponential interpolation uses elapsed time rather than assuming a fixed refresh rate.
func smooth(_ previous: Float, target: Float, dt: Double, tau: Double) -> Float {
    previous + (target-previous) * Float(1-exp(-max(0,dt)/max(0.001,tau)))
}

/// RMS hysteresis keeps quiet FFT work and GPU drawing paused while preserving capture.
struct SilenceGate {
    private var quiet = 0.0
    private var loud = 0.0
    private var silent = false
    /// Require 1.5 seconds quiet, fade 350 ms, then require 50 ms above the wake threshold.
    mutating func update(db: Double, dt: Double) -> Double {
        if db > -60 { loud += dt } else { loud = 0 }
        if loud >= 0.05 { quiet = 0; silent = false }
        if db < -65 { quiet += dt } else if !silent { quiet = 0 }
        if quiet >= 1.85 { silent = true }
        return silent ? 0 : max(0,1-max(0,quiet-1.5)/0.35)
    }
}

/// 8192-point Hann FFT; stereo powers are averaged after transforms to preserve antiphase signals.
final class SpectrumAnalyzer {
    let sampleRate: Double
    private let n = 8192
    private let fft: FFTSetup
    private var window = [Float](repeating:0,count:8192)
    private var real = [Float](repeating:0,count:8192)
    private var imag = [Float](repeating:0,count:8192)
    private var powers = [Float](repeating:0,count:4097)
    private var channelPowers = [[Float](repeating:0,count:4097), [Float](repeating:0,count:4097)]
    private var history = [Float](repeating:0,count:16384)
    private var ordered = [Float](repeating:0,count:16384)
    private var position = 0
    private var received = 0
    private var hop = 0
    private var smoothed = [Float]()
    private var latestTargets = [Float]()
    private var channelMode = ""
    private var frequencyMin: Double?
    private var frequencyMax: Double?
    private var lastTime = 0.0
    private var sequence: UInt64 = 0
    private var signalTime = 0.0
    private var signalOpacity = 1.0
    private var gate = SilenceGate()
    private var windowSum: Float = 0

    /// Allocate FFT and scratch storage on the control/DSP queue, outside the IO callback.
    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        fft = vDSP_create_fftsetup(13, FFTRadix(kFFTRadix2))!
        for i in 0..<n { window[i] = Float(0.5-0.5*cos(2 * .pi * Double(i)/Double(n-1))) }
        windowSum = window.reduce(0,+)
    }
    deinit { vDSP_destroy_fftsetup(fft) }

    /// Retain a circular analysis window and emit only after each hop of 1024 new frames.
    func ingest(_ input: [Float], count: Int, settings: Settings, timestamp: Double) -> SpectrumFrame? {
        resetLayoutIfNeeded(settings: settings)
        // 2026-09-11: RMS wake-up is independent of the 8192-frame FFT warmup.
        var power = 0.0
        for x in input.prefix(count*2) where x.isFinite { power += Double(x)*Double(x) }
        let db = 10*log10(max(1e-16,power/Double(max(1,count*2))))
        let duration = Double(count)/sampleRate
        let signalDT = signalTime == 0 ? duration : min(duration,max(0,timestamp-signalTime))
        signalTime = timestamp
        signalOpacity = gate.update(db: db, dt: signalDT)
        for i in 0..<count {
            history[position*2] = input[i*2]; history[position*2+1] = input[i*2+1]
            position = (position+1)%n; received = min(n,received+1); hop += 1
        }
        guard received == n, hop >= 1024 else {
            sequence &+= 1
            let bands = received < n ? [Float](repeating: 0, count: settings.barCount) : smoothed
            return SpectrumFrame(bands: bands, rmsDB: db, timestamp: timestamp, sequence: sequence, opacity: signalOpacity, targetBands: latestTargets, channelMode: settings.channelMode, frequencyMin: settings.frequencyMin, frequencyMax: settings.frequencyMax)
        }
        hop %= 1024
        for i in 0..<n {
            ordered[i*2] = history[((position+i)%n)*2]
            ordered[i*2+1] = history[((position+i)%n)*2+1]
        }
        return analyze(pcm:ordered,count:n,settings:settings,timestamp:timestamp,advanceSignal:false)
    }

    /// 2026-09-11: Advance signal absence separately from PCM, avoiding fabricated samples during empty polls.
    func idle(settings: Settings, timestamp: Double) -> SpectrumFrame {
        resetLayoutIfNeeded(settings: settings)
        let dt = lastTime == 0 ? 0 : max(0,timestamp-lastTime)
        lastTime = timestamp; sequence &+= 1
        received = 0; hop = 0
        let opacity = gate.update(db: -160, dt: signalTime == 0 ? 0 : max(0,timestamp-signalTime))
        signalTime = timestamp; signalOpacity = opacity
        if smoothed.count != settings.barCount { smoothed = [Float](repeating: 0, count: settings.barCount) }
        for i in smoothed.indices { smoothed[i] = smooth(smoothed[i], target: 0, dt: dt, tau: settings.releaseMs/1000) }
        latestTargets = [Float](repeating: 0, count: settings.barCount)
        return SpectrumFrame(bands: smoothed, rmsDB: -160, timestamp: timestamp, sequence: sequence, opacity: opacity, targetBands: latestTargets, channelMode: settings.channelMode, frequencyMin: settings.frequencyMin, frequencyMax: settings.frequencyMax)
    }

    /// Normalize per-channel FFT power, aggregate overlap-weighted logarithmic bins, then smooth.
    func analyze(pcm: [Float], count: Int, settings: Settings, timestamp: Double, smoothing: Bool = true, advanceSignal: Bool = true) -> SpectrumFrame {
        resetLayoutIfNeeded(settings: settings)
        let dt = lastTime == 0 ? Double(1024)/sampleRate : max(0,timestamp-lastTime)
        lastTime = timestamp; sequence &+= 1
        var total = 0.0
        for x in pcm.prefix(count*2) where x.isFinite { total += Double(x)*Double(x) }
        let db = 10*log10(max(1e-16,total/Double(max(1,count*2))))
        if advanceSignal { signalOpacity = gate.update(db:db,dt:dt); signalTime = timestamp }
        let opacity = signalOpacity
        var bands = [Float](repeating:0,count:settings.barCount)
        // RMS still runs during silence; skip both FFTs after fade completes.
        if opacity > 0 || !smoothing {
            powers.withUnsafeMutableBufferPointer { $0.initialize(repeating:0) }
            channelPowers[0].withUnsafeMutableBufferPointer { $0.initialize(repeating:0) }
            channelPowers[1].withUnsafeMutableBufferPointer { $0.initialize(repeating:0) }
            for channel in 0..<2 {
                var mean: Float = 0
                for i in 0..<n { mean += pcm[i*2+channel].isFinite ? pcm[i*2+channel] : 0 }
                mean /= Float(n)
                for i in 0..<n { real[i] = ((pcm[i*2+channel].isFinite ? pcm[i*2+channel] : 0)-mean)*window[i]; imag[i] = 0 }
                real.withUnsafeMutableBufferPointer { r in imag.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp:r.baseAddress!,imagp:im.baseAddress!)
                    vDSP_fft_zip(fft,&split,1,13,FFTDirection(FFT_FORWARD))
                }}
                // One-sided power factor 2 and stereo average 1/2 cancel in merged mode.
                for i in 1...n/2 {
                    let channelPower = (real[i]*real[i]+imag[i]*imag[i])/(windowSum*windowSum)
                    channelPowers[channel][i] = channelPower
                    powers[i] += channelPower
                }
            }
            if settings.channelMode == "stereo" {
                let channelBarCount = settings.barCount / 2
                // 2026-09-11: Each half has its own full logarithmic range; factor 2 restores one-sided single-channel power.
                aggregate(source: channelPowers[0], scale: 2, settings: settings, into: &bands, range: 0..<channelBarCount)
                aggregate(source: channelPowers[1], scale: 2, settings: settings, into: &bands, range: channelBarCount..<settings.barCount)
            } else {
                aggregate(source: powers, scale: 1, settings: settings, into: &bands, range: 0..<settings.barCount)
            }
        }
        latestTargets = bands
        if smoothed.count != bands.count { smoothed = [Float](repeating:0,count:bands.count) }
        if smoothing {
            for i in bands.indices { smoothed[i] = smooth(smoothed[i],target:bands[i],dt:dt,tau:bands[i]>smoothed[i] ? 0.03 : settings.releaseMs/1000) }
            bands = smoothed
        }
        return SpectrumFrame(bands:bands,rmsDB:db,timestamp:timestamp,sequence:sequence,opacity:opacity,targetBands:latestTargets,channelMode:settings.channelMode,frequencyMin:settings.frequencyMin,frequencyMax:settings.frequencyMax)
    }

    /// 2026-09-11: Aggregate only the configured range, capped by Nyquist so low-rate devices cannot address invalid FFT bins.
    private func aggregate(source: [Float], scale: Double, settings: Settings, into bands: inout [Float], range: Range<Int>) {
        let binHz = sampleRate/Double(n)
        let lower = settings.frequencyMin
        let upper = min(settings.frequencyMax, sampleRate/2)
        // A device whose Nyquist frequency does not exceed the configured floor has no analyzable bins.
        guard range.count > 0, binHz.isFinite, binHz > 0, lower.isFinite, upper.isFinite, lower > 0, upper > lower else { return }
        for band in range {
            let localBand = band - range.lowerBound
            let low = lower*pow(upper/lower,Double(localBand)/Double(range.count))
            let high = lower*pow(upper/lower,Double(localBand+1)/Double(range.count))
            var power = 0.0, weight = 0.0
            if high-low < binHz {
                // Adjacent narrow low-frequency bars interpolate shared bins; they are not independent resolution.
                let center = sqrt(low*high)/binHz
                let i = min(n/2-1,max(1,Int(center))), fraction = max(0,min(1,center-Double(i)))
                power = Double(source[i])*(1-fraction)+Double(source[i+1])*fraction
            } else {
                for i in max(1,Int(low/binHz-0.5))...min(n/2,Int(high/binHz+0.5)) {
                    let overlap = max(0,min(high,(Double(i)+0.5)*binHz)-max(low,(Double(i)-0.5)*binHz))
                    power += Double(source[i])*overlap; weight += overlap
                }
                power /= max(weight,1e-12)
            }
            let dbBand = 10*log10(max(power * scale,1e-16))+settings.sensitivityDB
            bands[band] = Float(min(1,max(0,(dbBand+72)/72)))
        }
    }

    /// 2026-09-11: Clear values whose indices describe a previous channel or configured-frequency layout.
    private func resetLayoutIfNeeded(settings: Settings) {
        guard channelMode != settings.channelMode || smoothed.count != settings.barCount || frequencyMin != settings.frequencyMin || frequencyMax != settings.frequencyMax else { return }
        // Mode and range changes redefine every bar index, so neither display history nor FFT targets are reusable.
        channelMode = settings.channelMode
        frequencyMin = settings.frequencyMin
        frequencyMax = settings.frequencyMax
        smoothed = [Float](repeating: 0, count: settings.barCount)
        latestTargets = [Float](repeating: 0, count: settings.barCount)
        if received == n { hop = 0 }
    }
}
