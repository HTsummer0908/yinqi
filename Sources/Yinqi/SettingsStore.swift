// 2026-09-11: Route user-visible labels and messages through the process-selected localization resources.
import Foundation
import Combine

/// Main-thread observable settings with bounded debounce and atomic JSON replacement.
final class SettingsStore: ObservableObject {
    @Published var value: Settings { didSet { onChange?(value.validated()); scheduleSave() } }
    /// 2026-09-11: Mirror transient edit mode for settings without persisting or restarting capture.
    @Published var isEditing = false
    @Published var warning: String?
    /// 2026-09-11: Report explicit import/export results in About without persistent logging.
    @Published var transferMessage: String?
    /// 2026-09-11: Runtime backend remains fixed until process exit; it is never exported.
    @Published var activeRendererBackend: String?
    /// 2026-09-11: A reverted choice cancels the pending restart without touching the current renderer.
    var rendererRestartRequired: Bool {
        activeRendererBackend.map { $0 != value.validated().rendererBackend } ?? false
    }
    /// 2026-09-11: Language changes apply in a fresh process, like renderer changes.
    @Published var activeLanguageChoice: String?
    var languageRestartRequired: Bool { activeLanguageChoice.map { $0 != value.language } ?? false }
    var restartRequired: Bool { rendererRestartRequired || languageRestartRequired }
    var onChange: ((Settings) -> Void)?
    private let url: URL
    private var pending: DispatchWorkItem?

    /// Corrupt local files fall back to defaults and produce one visible warning.
    init(url: URL? = nil, legacyURL: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("local.xinfei.yinqi/settings.json")
        // 2026-09-11: Copy the pre-rename preferences once; never overwrite an existing Yinqi file or remove the original.
        var migrationWarning: String?
        if !FileManager.default.fileExists(atPath: self.url.path), url == nil || legacyURL != nil {
            let legacy = legacyURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("local.xinfei.soundbar/settings.json")
            if FileManager.default.fileExists(atPath: legacy.path) {
                do {
                    let data = try Data(contentsOf: legacy)
                    _ = try Settings.decode(data)
                    try FileManager.default.createDirectory(at: self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: self.url, options: .atomic)
                } catch { migrationWarning = L("旧版设置迁移失败：%@", String(describing: error.localizedDescription)) }
            }
        }
        value = Settings()
        warning = migrationWarning
        if FileManager.default.fileExists(atPath:self.url.path) {
            do { value = try Settings.decode(Data(contentsOf:self.url)) }
            catch { warning = L("设置文件损坏，已恢复默认值：%@", String(describing: error.localizedDescription)) }
        }
    }

    /// 2026-09-11: Export a versioned portable envelope, excluding machine identity and runtime intent.
    func exportData() throws -> Data {
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value.validated())) as! [String: Any]
        for key in ["screenHint", "hasLaunched", "spectrumEnabled"] { fields.removeValue(forKey: key) }
        return try JSONSerialization.data(withJSONObject: ["format": "yinqi-settings", "version": 1, "settings": fields], options: [.prettyPrinted, .sortedKeys])
    }

    /// 2026-09-11: Validate and persist before applying; failed imports leave the current configuration untouched.
    func importData(_ data: Data) throws {
        guard data.count <= 1_048_576,
              let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope["format"] as? String == "yinqi-settings",
              envelope["version"] as? Int == 1,
              let fields = envelope["settings"] as? [String: Any], !fields.isEmpty else {
            throw CocoaError(.coderReadCorrupt)
        }
        var imported = try Settings.decode(JSONSerialization.data(withJSONObject: fields))
        imported.hasLaunched = value.hasLaunched
        imported.spectrumEnabled = value.spectrumEnabled
        imported.screenHint = ""
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(imported).write(to: url, options: .atomic)
        pending?.cancel(); pending = nil
        value = imported
        warning = nil
    }

    /// Coalesce continuous controls; the application has only one main-thread writer.
    private func scheduleSave() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.3,execute:work)
    }

    /// 2026-09-11: Report atomic-save success so restart never proceeds after a failed write.
    @discardableResult
    func saveNow() -> Bool {
        pending?.cancel(); pending = nil
        do {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            try encoder.encode(value.validated()).write(to:url,options:.atomic)
            return true
        } catch { warning = L("设置保存失败：%@", String(describing: error.localizedDescription)); return false }
    }
}
