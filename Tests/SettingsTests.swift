import Foundation
import CoreGraphics
/// Configuration inputs are untrusted local data and must not hide the control window permanently.
@main struct SettingsTests {
    /// 2026-09-11: Verify portable round trips, runtime preservation, atomic rejection and failed persistence.
    static func portableConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = SettingsStore(url: directory.appendingPathComponent("source.json"))
        source.value.peakFallSpeed = 14; source.value.frequencyMax = 12000
        source.value.screenHint = "other-display"; source.value.spectrumEnabled = false
        let data = try source.exportData()
        let envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let fields = envelope["settings"] as! [String: Any]
        assert(fields["screenHint"] == nil && fields["spectrumEnabled"] == nil && fields["hasLaunched"] == nil)
        let destinationURL = directory.appendingPathComponent("destination.json")
        let destination = SettingsStore(url: destinationURL)
        destination.value.hasLaunched = true; destination.value.spectrumEnabled = true
        try destination.importData(data)
        assert(destination.value.peakFallSpeed == 14 && destination.value.frequencyMax == 12000)
        assert(destination.value.hasLaunched && destination.value.spectrumEnabled && destination.value.screenHint.isEmpty)
        assert(SettingsStore(url: destinationURL).value == destination.value)
        let before = destination.value
        let diskBefore = try Data(contentsOf: destinationURL)
        for invalid in [Data("{}".utf8), Data("broken".utf8), Data("{\"format\":\"yinqi-settings\",\"version\":2,\"settings\":{\"gap\":2}}".utf8)] {
            do { try destination.importData(invalid); assertionFailure("invalid import accepted") } catch {}
            assert(destination.value == before)
            let diskAfter = try Data(contentsOf: destinationURL)
            assert(diskAfter == diskBefore)
        }
        let blocked = SettingsStore(url: destinationURL.appendingPathComponent("child.json"))
        let blockedBefore = blocked.value
        do { try blocked.importData(data); assertionFailure("write should fail") } catch {}
        assert(blocked.value == blockedBefore)
        print("PASS: portable configuration round trip, runtime preservation, invalid import and write failure rollback")
    }

    /// Exercise missing fields, unknown keys, corruption, bounds, and a negative-coordinate screen.
    static func main() throws {
        try portableConfiguration()

        // 2026-09-11: Advanced UI mode must persist without quantizing existing custom values.
        var detailed = Settings(); detailed.advancedSettings = true; detailed.peakFallSpeed = 14; detailed.releaseMs = 289
        let detailedReload = try Settings.decode(JSONEncoder().encode(detailed))
        assert(detailedReload.advancedSettings && detailedReload.peakFallSpeed == 14)
        detailed.advancedSettings = false
        let simpleReload = try Settings.decode(JSONEncoder().encode(detailed))
        assert(!simpleReload.advancedSettings && simpleReload.releaseMs == 289 && simpleReload.peakFallSpeed == 14)
        let defaultMode = try Settings.decode(Data("{}".utf8))
        assert(!defaultMode.advancedSettings)
        // 2026-09-11: Verify custom migration, unlimited restoration, presets and persisted mode.
        let legacyRate = try Settings.decode(Data("{\"frameRate\":144}".utf8))
        assert(legacyRate.customFrameRate && legacyRate.frameRate == 144)
        let unlimited = legacyRate.settingUnlimited(true)
        assert(unlimited.frameRate == 0 && unlimited.lastLimitedFrameRate == 144)
        assert(unlimited.settingUnlimited(false).frameRate == 144)
        let preset = legacyRate.settingCustomFrameRate(false)
        assert(preset.frameRate == 120 && !preset.customFrameRate)
        let custom = preset.settingCustomFrameRate(true)
        assert(custom.customFrameRate && custom.frameRate == 120)
        let customReloaded = try Settings.decode(JSONEncoder().encode(custom))
        assert(customReloaded == custom)
        // 2026-09-11: Symmetric gain bounds and retired background fields remain compatible with old JSON.
        for (input, expected) in [(-30.0, -24.0), (-24, -24), (0, 0), (24, 24), (30, 24)] {
            var gain = Settings(); gain.sensitivityDB = input
            assert(gain.validated().sensitivityDB == expected)
        }
        let retired = try Settings.decode(Data("{\"backgroundOpacity\":1,\"sensitivityDB\":-24}".utf8))
        assert(retired.sensitivityDB == -24)
        let retiredOutput = try JSONSerialization.jsonObject(with: JSONEncoder().encode(retired)) as! [String:Any]
        assert(retiredOutput["backgroundOpacity"] == nil)
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
        // 2026-09-11: Verify rename migration preserves the source and never overwrites new settings.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = folder.appendingPathComponent("legacy.json")
        let migratedURL = folder.appendingPathComponent("new/settings.json")
        var old = Settings(); old.barCount = 128
        try JSONEncoder().encode(old).write(to: legacy)
        let migrated = SettingsStore(url: migratedURL, legacyURL: legacy)
        assert(migrated.value.barCount == 128 && FileManager.default.fileExists(atPath: legacy.path))
        migrated.value.barCount = 32; migrated.saveNow()
        assert(SettingsStore(url: migratedURL, legacyURL: legacy).value.barCount == 32)
        let invalidURL = folder.appendingPathComponent("invalid.json")
        try Data("broken".utf8).write(to: legacy)
        let invalidMigration = SettingsStore(url: invalidURL, legacyURL: legacy)
        assert(invalidMigration.warning != nil && !FileManager.default.fileExists(atPath: invalidURL.path))
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
