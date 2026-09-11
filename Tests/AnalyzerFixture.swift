import Foundation
/// Generate known signals only in the test executable.
extension SpectrumAnalyzer {
    /// Bypass display smoothing to inspect actual frequency localization and channel power.
    func analyzeForTest(frequencies: [Double], antiphase: Bool, settings: Settings = Settings()) -> SpectrumFrame {
        var pcm = [Float]()
        for i in 0..<8192 {
            let x = Float(frequencies.reduce(0.0) { $0 + 0.2 * sin(2 * .pi * $1 * Double(i) / sampleRate) })
            pcm.append(x); pcm.append(antiphase ? -x : x)
        }
        return analyze(pcm: pcm, count: 8192, settings: settings, timestamp: 1, smoothing: false)
    }
}
