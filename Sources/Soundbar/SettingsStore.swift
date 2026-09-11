import Foundation
import Combine

/// Main-thread observable settings with bounded debounce and atomic JSON replacement.
final class SettingsStore: ObservableObject {
    @Published var value: Settings { didSet { onChange?(value.validated()); scheduleSave() } }
    @Published var warning: String?
    var onChange: ((Settings) -> Void)?
    private let url: URL
    private var pending: DispatchWorkItem?

    /// Corrupt local files fall back to defaults and produce one visible warning.
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("local.xinfei.soundbar/settings.json")
        value = Settings()
        if FileManager.default.fileExists(atPath:self.url.path) {
            do { value = try Settings.decode(Data(contentsOf:self.url)) }
            catch { warning = "设置文件损坏，已恢复默认值：\(error.localizedDescription)" }
        }
    }

    /// Coalesce continuous controls; the application has only one main-thread writer.
    private func scheduleSave() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.3,execute:work)
    }

    /// Foundation atomic writing creates a temporary sibling then replaces the destination.
    func saveNow() {
        pending?.cancel(); pending = nil
        do {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            try encoder.encode(value.validated()).write(to:url,options:.atomic)
        } catch { warning = "设置保存失败：\(error.localizedDescription)" }
    }
}
