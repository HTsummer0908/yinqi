import Foundation

/// Deterministic FFT tests; generated PCM is test input and never used by the application UI.
@main struct DSPTests {
    /// Check peak location, phase invariance, finite silence, and smoothing independent of dt partition.
    static func main() {
        for rate in [44100.0, 48000.0, 96000.0] {
            for frequency in [100.0, 1000.0, 10000.0] {
                let a = SpectrumAnalyzer(sampleRate: rate)
                let frame = a.analyzeForTest(frequencies: [frequency], antiphase: false)
                let inverse = a.analyzeForTest(frequencies: [frequency], antiphase: true)
                let expected = Int(log(frequency / 20) / log(min(20000,rate/2) / 20) * 64)
                let peak = frame.bands.enumerated().max(by: {$0.element < $1.element})!.offset
                assert(abs(peak - expected) <= 2, "peak \(frequency) \(rate) got \(peak) expected \(expected)")
                assert(zip(frame.bands, inverse.bands).allSatisfy { abs($0-$1) < 0.0001 })
            }
        }
        let a = SpectrumAnalyzer(sampleRate: 48000)
        assert(a.analyzeForTest(frequencies: [], antiphase: false).bands.allSatisfy { $0 == 0 })
        let dual = a.analyzeForTest(frequencies: [100,10000], antiphase: false)
        assert(dual.bands[14] > 0.2 && dual.bands[57] > 0.2)
        for count in [16,32,64,128] {
            var settings = Settings(); settings.barCount = count
            let f = a.analyzeForTest(frequencies: [1000], antiphase: false, settings: settings)
            assert(f.bands.count == count && f.bands.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        }
        let idle = a.idle(settings: Settings(), timestamp: 10)
        assert(idle.opacity == 0 && idle.rmsDB == -160)
        let short = [Float](repeating: 0.1, count: 2048)
        _ = a.ingest(short, count: 1024, settings: Settings(), timestamp: 10.02)
        _ = a.ingest(short, count: 1024, settings: Settings(), timestamp: 10.04)
        let warmup = a.ingest(short, count: 1024, settings: Settings(), timestamp: 10.06)
        assert(warmup != nil && warmup!.opacity == 1 && warmup!.bands.allSatisfy { $0 == 0 }, "RMS must wake before FFT warmup completes")
        let whole = smooth(0, target: 1, dt: 0.1, tau: 0.03)
        let half = smooth(smooth(0, target: 1, dt: 0.05, tau: 0.03), target: 1, dt: 0.05, tau: 0.03)
        assert(abs(whole-half) < 0.00001)
        var gate = SilenceGate()
        _ = gate.update(db: -80, dt: 1.5)
        assert(gate.update(db: -80, dt: 0.36) == 0)
        assert(gate.update(db: -50, dt: 0.06) == 1)
        testStereoChannelsRemainIndependent()
        testStereoChannelsLocateDifferentFrequencies()
        testModeSwitchClearsPublishedHistory()
        testMergedModePreservesAntiphasePower()
        testConfiguredRangeRemapsPeak()
        testToneOutsideConfiguredRangeDoesNotRaiseBars()
        testFrequencyRangeSwitchClearsPublishedHistory()
        testLowSampleRateBelowConfiguredRangeIsSafe()
        print("PASS: FFT localization, configurable frequency range, low-rate bounds, independent stereo channels, mode and range switching, merged antiphase compatibility, target publication, smoothing, silence recovery")
    }

    /// Verify a signal in one channel cannot create bars in the other stereo half.
    static func testStereoChannelsRemainIndependent() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000)
        let settings = stereoSettings()
        let left = analyzer.analyze(pcm: stereoPCM(left: 1000, right: nil), count: 8192, settings: settings, timestamp: 1, smoothing: false)
        let right = analyzer.analyze(pcm: stereoPCM(left: nil, right: 1000), count: 8192, settings: settings, timestamp: 2, smoothing: false)
        assert(left.bands[0..<32].max()! > 0.2 && left.bands[32..<64].allSatisfy { $0 == 0 }, "left-only input leaked into right bars")
        assert(right.bands[32..<64].max()! > 0.2 && right.bands[0..<32].allSatisfy { $0 == 0 }, "right-only input leaked into left bars")
        assert(left.targetBands == left.bands && right.targetBands == right.bands, "FFT frames must publish unsmoothed targets")
    }

    /// Verify each stereo half owns a complete 20 Hz...20 kHz logarithmic layout.
    static func testStereoChannelsLocateDifferentFrequencies() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000)
        let frame = analyzer.analyze(pcm: stereoPCM(left: 100, right: 10000), count: 8192, settings: stereoSettings(), timestamp: 1, smoothing: false)
        let leftPeak = frame.bands[0..<32].enumerated().max(by: { $0.element < $1.element })!.offset
        let rightPeak = frame.bands[32..<64].enumerated().max(by: { $0.element < $1.element })!.offset
        assert(abs(leftPeak - 7) <= 2, "left frequency used the wrong logarithmic layout: \(leftPeak)")
        assert(abs(rightPeak - 28) <= 2, "right frequency used the wrong logarithmic layout: \(rightPeak)")
    }

    /// Verify a layout change cannot publish values or targets from the previous mode.
    static func testModeSwitchClearsPublishedHistory() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000)
        var merged = Settings(); merged.releaseMs = 500
        let active = analyzer.analyze(pcm: stereoPCM(left: 1000, right: 1000), count: 8192, settings: merged, timestamp: 1)
        assert(active.bands.max()! > 0)
        assert(active.targetBands!.max()! > active.bands.max()!, "published targets must remain unsmoothed")
        let retained = analyzer.ingest([Float](repeating: 0, count: 2048), count: 1024, settings: merged, timestamp: 1.01)!
        assert(retained.targetBands == active.targetBands, "non-FFT frames must retain the latest targets")
        let switched = analyzer.ingest([Float](repeating: 0, count: 2048), count: 1024, settings: stereoSettings(), timestamp: 1.02)!
        assert(switched.bands.count == 64 && switched.bands.allSatisfy { $0 == 0 }, "mode switch leaked merged bars")
        assert(switched.targetBands?.count == 64 && switched.targetBands!.allSatisfy { $0 == 0 }, "mode switch leaked merged targets")
        let idle = analyzer.idle(settings: stereoSettings(), timestamp: 1.04)
        assert(idle.targetBands?.allSatisfy { $0 == 0 } == true, "idle targets must be zero")
    }

    /// Verify merged mode still averages channel powers so antiphase cannot cancel.
    static func testMergedModePreservesAntiphasePower() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000)
        let inPhase = analyzer.analyzeForTest(frequencies: [1000], antiphase: false)
        let antiphase = analyzer.analyzeForTest(frequencies: [1000], antiphase: true)
        assert(inPhase.bands.count == 64 && zip(inPhase.bands, antiphase.bands).allSatisfy { abs($0 - $1) < 0.0001 })
    }

    /// Verify a configured logarithmic range determines the tone's output-bar position.
    static func testConfiguredRangeRemapsPeak() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000)
        var settings = Settings()
        settings.frequencyMin = 100
        settings.frequencyMax = 10000
        let frame = analyzer.analyzeForTest(frequencies: [1000], antiphase: false, settings: settings)
        let peak = frame.bands.enumerated().max(by: { $0.element < $1.element })!.offset
        assert(abs(peak - 32) <= 2, "configured range did not remap 1 kHz near its logarithmic midpoint: \(peak)")
        assert(frame.frequencyMin == 100 && frame.frequencyMax == 10000, "analysis frame omitted its frequency-layout metadata")
    }

    /// Verify frequencies outside the selected analysis range do not masquerade as an in-range peak.
    static func testToneOutsideConfiguredRangeDoesNotRaiseBars() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000)
        var settings = Settings()
        settings.frequencyMin = 1000
        settings.frequencyMax = 8000
        let frame = analyzer.analyzeForTest(frequencies: [93.75], antiphase: false, settings: settings)
        assert(frame.bands.max()! < 0.05, "out-of-range tone raised an in-range bar: \(frame.bands.max()!)")
    }

    /// Verify a frequency-layout change clears smoothed bars and targets before the next FFT is ready.
    static func testFrequencyRangeSwitchClearsPublishedHistory() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000)
        var original = Settings()
        original.releaseMs = 500
        let active = analyzer.analyzeForTest(frequencies: [1000], antiphase: false, settings: original)
        assert(active.bands.max()! > 0)
        var narrowed = original
        narrowed.frequencyMin = 500
        narrowed.frequencyMax = 5000
        let switched = analyzer.ingest([Float](repeating: 0, count: 2048), count: 1024, settings: narrowed, timestamp: 1.01)!
        assert(switched.bands.allSatisfy { $0 == 0 }, "range switch leaked smoothed bars from the previous layout")
        assert(switched.targetBands?.allSatisfy { $0 == 0 } == true, "range switch leaked targets from the previous layout")
        assert(switched.frequencyMin == 500 && switched.frequencyMax == 5000, "non-FFT frame published stale frequency metadata")
    }

    /// Verify a Nyquist limit at or below the configured lower bound yields finite zero bars without indexing past FFT storage.
    static func testLowSampleRateBelowConfiguredRangeIsSafe() {
        let analyzer = SpectrumAnalyzer(sampleRate: 30)
        let frame = analyzer.analyzeForTest(frequencies: [5], antiphase: false)
        assert(frame.bands.count == 64 && frame.bands.allSatisfy { $0 == 0 && $0.isFinite }, "invalid low-rate analysis range produced nonzero or nonfinite bars")
        assert(frame.frequencyMin == 20 && frame.frequencyMax == 20000, "frame metadata must describe the configured layout even when Nyquist truncates analysis")
    }

    /// Build validated stereo settings through the same decoded configuration boundary used by the app.
    static func stereoSettings() -> Settings {
        try! Settings.decode(Data("{\"channelMode\":\"stereo\"}".utf8))
    }

    /// Generate deterministic interleaved stereo PCM with independently selectable channel tones.
    static func stereoPCM(left: Double?, right: Double?) -> [Float] {
        var pcm = [Float](); pcm.reserveCapacity(16384)
        for i in 0..<8192 {
            let time = Double(i) / 48000
            pcm.append(left.map { Float(0.2 * sin(2 * .pi * $0 * time)) } ?? 0)
            pcm.append(right.map { Float(0.2 * sin(2 * .pi * $0 * time)) } ?? 0)
        }
        return pcm
    }
}
