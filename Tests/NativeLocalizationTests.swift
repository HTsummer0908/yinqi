import Foundation

/// 2026-09-11: Run inside a disposable .app so Foundation uses the real main-bundle language negotiation.
@main struct NativeLocalizationTests {
    static func main() {
        let code=CommandLine.arguments[1]
        Localization.bootstrap(choice:code)
        precondition(Bundle.main.preferredLocalizations.first==code)
        let expected=code == "zh-Hans" ? "音栖" : (code.hasPrefix("zh-") ? "音棲" : "Yinqi")
        precondition(Bundle.main.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String == expected)
        precondition(Bundle.main.object(forInfoDictionaryKey:"NSAudioCaptureUsageDescription") as? String == L("只分析本机系统播放音频，不保存或上传声音。"))
        print("PASS: native bootstrap, name and permission text for \(code)")
    }
}
