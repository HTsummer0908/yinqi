import Foundation

/// 2026-09-11: Validate fallback selection, packaged translations, formatting and portable language preferences.
@main struct LocalizationTests {
    /// Parse Apple's .strings format, not a custom test-only translation format.
    static func table(_ bundle: Bundle, _ code: String, _ name: String) throws -> [String:String] {
        let path = bundle.bundleURL.appendingPathComponent("Contents/Resources/\(code).lproj/\(name).strings")
        return try PropertyListSerialization.propertyList(from:Data(contentsOf:path),format:nil) as! [String:String]
    }

    static func main() throws {
        let bundle = Bundle(url:URL(fileURLWithPath:"build/Yinqi.app"))!
        let base = try table(bundle,"zh-Hans","Localizable")
        precondition(base.count >= 200)
        let cases: [([String],String)] = [(["zh-CN"],"zh-Hans"),(["zh-SG"],"zh-Hans"),(["zh-Hans-HK"],"zh-Hans"),(["zh-Hant-HK"],"zh-HK"),(["zh-MO"],"zh-HK"),(["zh-Hant-MO"],"zh-HK"),(["zh-Hant"],"zh-TW"),(["zh-TW"],"zh-TW"),(["fr-CA"],"fr"),(["de-AT"],"de"),(["ja-JP"],"ja"),(["ko-KR"],"ko"),(["es-ES","fr-FR"],"fr"),(["es-ES"],"en"),([],"en")]
        for (preferred,expected) in cases { precondition(AppLanguage.resolve("system",preferred:preferred)==expected) }
        precondition(AppLanguage.resolve("de",preferred:["zh-CN"])=="de")
        for language in AppLanguage.codes {
            let translations = try table(bundle,language,"Localizable")
            precondition(Set(translations.keys)==Set(base.keys))
            for (key,value) in translations {
                precondition(!value.isEmpty)
                precondition(key.components(separatedBy:"%@").count == value.components(separatedBy:"%@").count)
            }
            Localization.configure(language,bundle:bundle)
            precondition(L("语言")==translations["语言"])
            let version = L("版本 %@ · 构建 %@","1.0.1","32")
            precondition(version.contains("1.0.1") && version.contains("32") && !version.contains("%@"))
            let info = try table(bundle,language,"InfoPlist")
            precondition(info["CFBundleDisplayName"] == (language == "zh-Hans" ? "音栖" : (language.hasPrefix("zh-") ? "音棲" : "Yinqi")))
            precondition(info["NSAudioCaptureUsageDescription"] == translations["只分析本机系统播放音频，不保存或上传声音。"])
            print("PASS: \(language), \(translations.count) messages, placeholders and bundle display name")
        }
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let source=SettingsStore(url:directory.appendingPathComponent("a.json"))
        precondition(source.value.language=="system")
        source.activeLanguageChoice="system";source.activeRendererBackend="coreAnimation"
        source.value.language="fr"
        precondition(source.languageRestartRequired && source.restartRequired)
        precondition(source.saveNow())
        let loaded=SettingsStore(url:directory.appendingPathComponent("a.json"))
        precondition(loaded.value.language=="fr")
        let imported=SettingsStore(url:directory.appendingPathComponent("b.json"))
        imported.activeLanguageChoice="system"
        try imported.importData(source.exportData())
        precondition(imported.value.language=="fr" && imported.languageRestartRequired)
        source.value.language="system"
        precondition(!source.restartRequired)
        let unknown=try Settings.decode(Data("{\"language\":\"unknown\"}".utf8))
        precondition(unknown.language=="system")
        let export=String(data:try imported.exportData(),encoding:.utf8)!
        precondition(!export.contains("activeLanguageChoice"))
        print("PASS: system fallback, regional Chinese, persistence, import and deferred restart")
    }
}
