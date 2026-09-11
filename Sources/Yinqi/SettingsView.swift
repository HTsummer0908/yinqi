import SwiftUI

/// Settings edit portable preferences; capture and window operations remain coordinator actions.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    var showDiagnostics: () -> Void = {}
    var enableSpectrum: () -> Void = {}
    var hideSpectrum: () -> Void = {}
    var editSpectrum: () -> Void = {}
    var quickLayout: (String) -> Void = { _ in }

    @StateObject private var navigation = SettingsNavigation()

    /// 2026-09-11: Mount only the selected category; unrelated controls do not participate in layout.
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("音栖 Yinqi").font(.headline).padding(.bottom, 12)
                ForEach(SettingsCategory.allCases, id: \.self) { category in
                    Button {
                        // Commit any valid numeric draft before its category leaves the hierarchy.
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        navigation.category = category
                    } label: {
                        Label(category.rawValue, systemImage: category.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                            .background(navigation.category == category ? Color.accentColor.opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            // 2026-09-11: Include padded blank space in the plain button hit region.
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .accessibilityAddTraits(navigation.category == category ? .isSelected : [])
                }
                Spacer()
            }.padding(12).frame(width: 140).frame(maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            Form {
                switch navigation.category {
                case .general: generalSection
                case .spectrum: spectrumSection
                case .animation: animationSection
                case .appearance: appearanceSection
                case .placement: placementSection
                case .about: aboutSection
                }
            }.formStyle(.grouped).padding(12).frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
        // 2026-09-11: Let AppKit resize the content; the Form scrolls when a category exceeds the height.
        }.frame(minWidth: 681, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
    }

    /// 2026-09-11: Show local bundle metadata and developer information without background network requests.
    @ViewBuilder private var aboutSection: some View {
        Section("关于音栖") {
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text("音栖 Yinqi").font(.title2).bold()
                    Text("让声音栖于桌面。轻量的 macOS 系统音频频谱工具。")
                    Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知") · 构建 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent("开发者", value: "HTsummer0908")
            Link("开发者 GitHub", destination: URL(string: "https://github.com/HTsummer0908")!)
            Text("项目名称：yinqi · GitHub 仓库准备中")
                .foregroundStyle(.secondary)
        }
        Section("隐私与项目状态") {
            Text("音频仅在本机实时分析，不录制、不保存、不上传。仅持久化应用设置。")
            Text("诊断按需开启；应用不会自动检查更新或发送遥测。")
            Text("开源许可证待确定；正式发布信息以项目 README 为准。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Render only the general settings category.
    private var generalSection: some View {
    Section("Yinqi") {
        Text("只分析本机系统播放音频，不保存或上传声音。")
            .font(.caption).foregroundStyle(.secondary)
        // 2026-09-11: Use the persisted enable intent shared with the menu, while actions own capture lifecycle.
        Toggle("启用频谱", isOn: Binding(get: { store.value.spectrumEnabled }, set: { enabled in
            if enabled { enableSpectrum() } else { hideSpectrum() }
        }))
        Toggle("在 Dock 中显示", isOn: $store.value.showInDock)
        Text("关闭后仍可通过菜单栏频谱图标 打开设置。关闭设置窗口不会停止频谱。")
            .font(.caption).foregroundStyle(.secondary)
        Button("打开运行诊断…", action: showDiagnostics)
        if let warning = store.warning { Text(warning).foregroundStyle(.orange) }
        Button("恢复全部默认设置") {
            // Preserve launch history and live capture intent when restoring preferences.
            var defaults = Settings()
            defaults.hasLaunched = store.value.hasLaunched
            defaults.spectrumEnabled = store.value.spectrumEnabled
            store.value = defaults; store.saveNow()
        }
    }
    }

    /// Render only the spectrum settings category.
    private var spectrumSection: some View {
    Section("频谱") {
        Picker("声道", selection: $store.value.channelMode) {
            Text("合并声道").tag("merged")
            Text("左右声道").tag("stereo")
        }
        Picker("柱条总数", selection: $store.value.barCount) {
            ForEach([16,32,64,128], id: \.self) { Text("\($0)").tag($0) }
        }
        if store.value.channelMode == "stereo" {
            Picker("频率排列", selection: $store.value.stereoOrder) {
                Text("同向：低→高 | 低→高").tag("ascending")
                Text("低频在外侧：低→高 | 高→低").tag("lowOutside")
                Text("低频在中央：高→低 | 低→高").tag("lowInside")
            }
            Text(store.value.isVertical ? "从上到下分别为左、右声道，各 \(store.value.barCount / 2) 柱。" : "从左到右分别为左、右声道，各 \(store.value.barCount / 2) 柱。")
                .font(.caption).foregroundStyle(.secondary)
            NumericSettingRow(name: "声道额外间隔", value: $store.value.channelGap, range: 0...40, unit: "pt", step: 0.1)
        }
        NumericSettingRow(name: "最低频率", value: $store.value.frequencyMin, range: 20...(store.value.frequencyMax-1), unit: "Hz", step: 1)
        NumericSettingRow(name: "最高频率", value: $store.value.frequencyMax, range: (store.value.frequencyMin+1)...20000, unit: "Hz", step: 1)
        Text("默认 20–20,000 Hz；仅调整频谱显示范围，不改变播放声音。实际最高频率受采样率限制，窄低频柱共享 FFT 分辨率。")
            .font(.caption).foregroundStyle(.secondary)
    }
    }

    /// Render only the animation settings category.
    private var animationSection: some View {
    Section("动画") {
        Toggle("无限制（跟随屏幕最高刷新率）", isOn: unlimitedBinding)
        if store.value.frameRate != 0 {
            NumericSettingRow(name: "目标帧率", value: frameRateBinding, range: 10...1000, unit: "FPS", step: 1)
            HStack {
                ForEach([10,30,60,120,144,240], id: \.self) { rate in
                    Button("\(rate)") { store.value.frameRate = rate }
                }
            }
        }
        Text("实际帧率受屏幕和系统调度影响；静音淡出后暂停绘制。")
            .font(.caption).foregroundStyle(.secondary)
        NumericSettingRow(name: "灵敏度", value: $store.value.sensitivityDB, range: -24...24, unit: "dB", step: 0.1)
        NumericSettingRow(name: "回落时间", value: $store.value.releaseMs, range: 80...500, unit: "ms", step: 1)
    }
    }

    /// Render only the appearance settings category.
    private var appearanceSection: some View {
    Section("外观") {
        Picker("风格", selection: $store.value.style) {
            Text("极简纯色").tag("solid"); Text("渐变").tag("gradient"); Text("复古 LED").tag("led")
        }
        if store.value.style == "gradient" {
            Picker("渐变方向", selection: $store.value.gradientDirection) {
                Text("从左到右").tag("horizontal")
                Text("从下到上").tag("vertical")
            }
        }
        if store.value.style == "gradient" {
            ColorPicker("渐变起点", selection: colorBinding(1), supportsOpacity: false)
            ColorPicker("渐变终点", selection: colorBinding(2), supportsOpacity: false)
        } else {
            ColorPicker("主色 / LED", selection: colorBinding(0), supportsOpacity: false)
        }
        NumericSettingRow(name: "柱间距", value: $store.value.gap, range: 0...8, unit: "pt", step: 0.1)
        NumericSettingRow(name: "柱顶圆角", value: $store.value.cornerRadius, range: 0...8, unit: "pt", step: 0.1)
        Toggle("基部也应用圆角", isOn: $store.value.roundBase)
        Text("基部指贴边的一端；关闭时仅柱顶圆角。零柱间距连接相邻柱身，圆角处仍保留弧线。")
            .font(.caption).foregroundStyle(.secondary)
        NumericSettingRow(name: "柱条透明度", value: percentBinding(\Settings.barOpacity), range: 10...100, unit: "%", step: 1)
    }
    }

    /// Render only the placement settings category.
    private var placementSection: some View {
    Section("位置") {
        Picker("位置", selection: placementBinding) {
            Text("底部").tag("bottom"); Text("顶部").tag("top"); Text("左侧").tag("left"); Text("右侧").tag("right"); Text("自由").tag("free")
        }
        Picker("生长方向", selection: $store.value.growthDirection) {
            if store.value.isVertical {
                Text("向右").tag("right"); Text("向左").tag("left")
            } else {
                Text("向上").tag("up"); Text("向下").tag("down")
            }
        }
        HStack {
            Button("居中") { quickLayout("center") }
            Button("沿当前边铺满") { quickLayout("fill") }
            Button("调整 / 锁定悬浮窗", action: editSpectrum)
        }
        Text("铺满使用屏幕可用区域；编辑模式提供四边停靠、居中、铺满和锁定图标。侧边频率轴从上到下，柱条向屏幕内生长。")
            .font(.caption).foregroundStyle(.secondary)
        NumericSettingRow(name: "边缘间距", value: $store.value.edgeInset, range: 0...120, unit: "pt", step: 1)
    }
    }

    /// Zero encodes screen-following mode; returning to a fixed limit restores the default 60 FPS.
    private var unlimitedBinding: Binding<Bool> {
        Binding(get: { store.value.frameRate == 0 }, set: { store.value.frameRate = $0 ? 0 : 60 })
    }

    /// The UI edits integral target rates while JSON retains the integer representation.
    private var frameRateBinding: Binding<Double> {
        Binding(get: { Double(store.value.frameRate) }, set: { store.value.frameRate = Int($0.rounded()) })
    }

    /// Present opacity as a familiar percentage without changing the stored fraction schema.
    private func percentBinding(_ key: WritableKeyPath<Settings, Double>) -> Binding<Double> {
        Binding(get: { store.value[keyPath: key] * 100 }, set: { store.value[keyPath: key] = $0 / 100 })
    }

    /// Placement changes choose the natural direction; the direction control can override it later.
    private var placementBinding: Binding<String> {
        Binding(get: { store.value.placementMode }, set: { placement in
            store.value = store.value.placing(at: placement)
        })
    }

    /// Convert portable RGB triplets to the platform color picker and back.
    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(get: {
            let c = index == 0 ? store.value.primaryColor : store.value.gradientColors[index-1]
            return Color(red: c[0], green: c[1], blue: c[2])
        }, set: { color in
            guard let c = NSColor(color).usingColorSpace(.deviceRGB) else { return }
            let rgb = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
            if index == 0 { store.value.primaryColor = rgb } else { store.value.gradientColors[index-1] = rgb }
        })
    }
}

/// 2026-09-11: Keep a text draft so incomplete numbers do not mutate settings while the user types.
private struct NumericSettingRow: View {
    let name: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let step: Double
    @StateObject private var input = NumericDraft()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                // 2026-09-11: Explicit columns keep every slider and numeric field aligned across categories.
                Text(name).frame(width: 110, alignment: .leading)
                Slider(value: sliderBinding, in: range).frame(width: 180).accessibilityLabel(name)
                TextField(name, text: $input.text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder).frame(width: 76)
                    .multilineTextAlignment(.trailing).focused($focused)
                    .onSubmit { commit() }
                    .onExitCommand { sync(); focused = false }
                Text(unit).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
            }
            if input.invalid { Text("请输入 \(range.lowerBound.formatted())–\(range.upperBound.formatted()) 范围内的数字")
                .font(.caption).foregroundStyle(.red) }
        }
        .onAppear { sync() }
        .onChange(of: value) { _, _ in sync() }
        .onChange(of: focused) { _, active in if !active { commit() } }
    }

    /// 2026-09-11: Quantize values ourselves so SwiftUI does not create thousands of automatic tick marks.
    private var sliderBinding: Binding<Double> {
        Binding(get: { value }, set: { proposed in
            let rounded = min(range.upperBound, max(range.lowerBound, (proposed / step).rounded() * step))
            if rounded != value { value = rounded }
        })
    }

    /// Slider changes and successful submissions refresh the draft in the current locale.
    private func sync() { input.text = value.formatted(.number.grouping(.never).precision(.fractionLength(0...2))); input.invalid = false }

    /// Invalid or out-of-range input leaves the previous setting intact and displays an inline error.
    private func commit() {
        guard input.text != value.formatted(.number.grouping(.never).precision(.fractionLength(0...2))) else { return }
        guard let number = parsedSettingNumber(input.text, range: range) else { input.invalid = true; return }
        value = (number / step).rounded() * step
        sync()
    }
}


/// Reference-backed editing state also supports CLT SDKs without the optional SwiftUI State macro plugin.
private final class NumericDraft: ObservableObject {
    @Published var text = ""
    @Published var invalid = false
}


/// Category selection is transient UI state and never changes audio or saved user preferences.
private final class SettingsNavigation: ObservableObject {
    @Published var category = SettingsCategory.general
}

/// Stable sidebar categories group controls by the task the user wants to perform.
private enum SettingsCategory: String, CaseIterable {
    case general = "常规", spectrum = "频谱", animation = "动画", appearance = "外观", placement = "位置", about = "关于"
    /// Native symbols identify categories without additional image assets.
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .spectrum: return "waveform"
        case .animation: return "speedometer"
        case .appearance: return "paintpalette"
        case .placement: return "rectangle.arrowtriangle.2.outward"
        case .about: return "info.circle"
        }
    }
}
