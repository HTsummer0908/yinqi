import Foundation
import CoreGraphics
/// Configuration inputs are untrusted local data and must not hide the control window permanently.
@main struct SettingsTests {
    /// Exercise missing fields, unknown keys, corruption, bounds, and a negative-coordinate screen.
    static func main() throws {
        // 2026-09-11: New preferences must survive old-file migration and validated round trips.
        let next = try Settings.decode(Data("{\"channelMode\":\"stereo\",\"frameRate\":2,\"showInDock\":false}".utf8))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(next)) as! [String:Any]
        assert(encoded["channelMode"] as? String == "stereo", "stereo preference must persist")
        assert(encoded["frameRate"] as? Int == 10, "frame rate minimum must be 10")
        assert(encoded["showInDock"] as? Bool == false)
        assert(Settings().showInDock && Settings().frameRate == 60 && !Settings().hasLaunched)
        var preferences = Settings(); preferences.frameRate = 0; preferences.channelMode = "unknown"
        assert(preferences.validated().frameRate == 0 && preferences.validated().channelMode == "merged")
        preferences.frameRate = Int.max
        assert(preferences.validated().frameRate == 1000)
        assert(parsedSettingNumber("-3.5", range: -12...24) == -3.5)
        assert(parsedSettingNumber("2,5", range: 0...8, locale: Locale(identifier: "de_DE")) == 2.5)
        for text in ["-", "", "nan", "inf", "9", "2junk"] { assert(parsedSettingNumber(text, range: 0...8) == nil) }
        let side = try Settings.decode(Data("{\"placementMode\":\"left\",\"growthDirection\":\"right\",\"width\":80,\"height\":600}".utf8))
        let sideFrame = restoredFrame(side, safe: CGRect(x: 0, y: 0, width: 1200, height: 800))
        assert(sideFrame == CGRect(x: 8, y: 100, width: 80, height: 600), "left dock must retain vertical geometry")
        var rectangle = Settings(); rectangle.width=600; rectangle.height=80
        let area = CGRect(x:-1200,y:-200,width:1200,height:800)
        for edge in ["bottom","top","left","right"] {
            var dock = rectangle.placing(at:edge)
            let geometry = restoredFrame(dock,safe:area)
            assert(area.contains(geometry))
            assert(dock.isVertical ? geometry.size == CGSize(width:80,height:600) : geometry.size == CGSize(width:600,height:80))
            let centered = dock.centered(in: area, frame: geometry)
            let centerFrame = restoredFrame(centered, safe: area)
            assert(centered.placementMode == "free" && centerFrame.midX == area.midX && centerFrame.midY == area.midY)
            dock.layoutMode="fill"
            let filled = restoredFrame(dock,safe:area)
            assert(dock.isVertical ? filled.height == area.height : filled.width == area.width)
            let decodedDock = try Settings.decode(JSONEncoder().encode(dock))
            assert(decodedDock == dock)
            let horizontal = dock.placing(at:"bottom")
            assert(horizontal.width == 600 && horizontal.height == 80)
        }
        var frequency = Settings(); frequency.frequencyMin=25000; frequency.frequencyMax=10
        assert(frequency.validated().frequencyMin == 19999 && frequency.validated().frequencyMax == 20000)
        assert(Settings().channelGap == 0 && !Settings().roundBase)
        let s = try Settings.decode(Data("{\"barCount\":128,\"gap\":999,\"future\":true}".utf8))
        assert(s.barCount == 128 && s.gap == 8 && s.height == 96)
        do { _ = try Settings.decode(Data("{broken".utf8)); assertionFailure("must reject corrupt JSON") } catch {}
        var bad = Settings(); bad.x = .infinity; bad.height = .nan; bad.barCount = 999
        assert(bad.validated().x == 0 && bad.validated().height == 96 && bad.validated().barCount == 64)
        bad.placementMode = "free"; bad.x = 9000; bad.y = -9999; bad.width = 20000
        let safe = CGRect(x:-1920,y:-400,width:1920,height:1000)
        let frame = restoredFrame(bad,safe:safe)
        assert(safe.contains(frame) && frame.width == 1920)
        for count in [16,32,64,128] { let gap = min(8.0,240/Double(count)-1); assert((240-Double(count-1)*gap)/Double(count)>0) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("settings.json")
        let store = SettingsStore(url: url)
        store.value.barCount = 128; store.value.width = 640; store.saveNow()
        let restored = SettingsStore(url: url)
        assert(restored.value.barCount == 128 && restored.value.width == 640)
        try Data("broken".utf8).write(to: url)
        let corrupt = SettingsStore(url: url)
        assert(corrupt.value.barCount == 64 && corrupt.warning != nil)
        print("PASS: atomic save/reload, corruption warning, default merge, unknown fields, corruption, NaN, bounds, negative screen, 4 bar layouts")
    }
}
