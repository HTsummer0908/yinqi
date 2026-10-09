// SPDX-License-Identifier: MPL-2.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// 2026-09-11: Stable portable choices; regional Traditional Chinese variants have independent resources.
enum AppLanguage {
    static let codes = ["zh-Hans", "zh-HK", "zh-TW", "en", "fr", "de", "ja", "ko"]
    static let names = ["zh-Hans": "简体中文", "zh-HK": "繁體中文（港澳）", "zh-TW": "繁體中文（台灣）", "en": "English", "fr": "Français", "de": "Deutsch", "ja": "日本語", "ko": "한국어"]

    /// Match the ordered system preferences, including script/region aliases; unsupported systems fall back to English.
    static func resolve(_ choice: String, preferred: [String]) -> String {
        if codes.contains(choice) { return choice }
        for identifier in preferred {
            let code = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            let parts = code.split(separator: "-").map(String.init)
            if parts.first == "zh" {
                if parts.contains("hans") { return "zh-Hans" }
                if parts.contains("hk") || parts.contains("mo") { return "zh-HK" }
                if parts.contains("tw") || parts.contains("hant") { return "zh-TW" }
                return "zh-Hans"
            }
            if let base = parts.first, codes.contains(base) { return base }
        }
        return "en"
    }
}

/// 2026-09-11: Configure once before AppKit starts; all rendering/audio threads subsequently read a fixed language.
enum Localization {
    private(set) static var language = "zh-Hans"
    private static var resources: Bundle?
    static var locale: Locale { Locale(identifier: language) }

    /// Explicit bundle lookup also localizes dynamic AppKit strings, not only SwiftUI literal labels.
    static func configure(_ language: String, bundle: Bundle = .main) {
        self.language = language
        resources = bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    /// Keep system panels in the selected language without writing a persistent AppleLanguages override.
    static func bootstrap(choice: String) {
        let language = AppLanguage.resolve(choice, preferred: Locale.preferredLanguages)
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["AppleLanguages"] = [language]
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        configure(language)
    }

    /// Format placeholders as objects so translated word order may change without losing values.
    static func text(_ key: String, arguments: [String]) -> String {
        let value = resources?.localizedString(forKey: key, value: key, table: nil) ?? key
        guard !arguments.isEmpty else { return value }
        return String(format: value, locale: locale, arguments: arguments.map { $0 as CVarArg })
    }
}

/// 2026-09-11: Shared lookup for settings, native menus, accessibility, diagnostics and error messages.
func L(_ key: String, _ arguments: String...) -> String {
    Localization.text(key, arguments: arguments)
}
