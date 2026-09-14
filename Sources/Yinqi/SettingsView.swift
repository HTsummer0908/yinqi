// 2026-09-11: Route user-visible labels and messages through the process-selected localization resources.
import SwiftUI

/// Settings edit portable preferences; capture and window operations remain coordinator actions.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    var showDiagnostics: () -> Void = {}
    var enableSpectrum: () -> Void = {}
    var hideSpectrum: () -> Void = {}
    var editSpectrum: () -> Void = {}
    var importSettings: () -> Void = {}
    var exportSettings: () -> Void = {}
    var restartApplication: () -> Void = {}
    var quickLayout: (String) -> Void = { _ in }

    @StateObject private var navigation = SettingsNavigation()

    /// 2026-09-11: Mount only the selected category; unrelated controls do not participate in layout.
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("音栖 Yinqi")).font(.headline).padding(.bottom, 12)
                ForEach(SettingsCategory.allCases, id: \.self) { category in
                    Button {
                        // Commit any valid numeric draft before its category leaves the hierarchy.
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        navigation.category = category
                    } label: {
                        Label(L(category.rawValue), systemImage: category.symbol)
                            .lineLimit(1).minimumScaleFactor(0.8)
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
        Section(L("关于音栖")) {
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("音栖 Yinqi")).font(.title2).bold()
                    Text(L("让声音栖于桌面。轻量的 macOS 系统音频频谱工具。"))
                    Text(L("版本 %@ · 构建 %@", String(describing: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("未知")), String(describing: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? L("未知"))))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent(L("开发者"), value: "HTsummer0908")
            Link(L("开发者 GitHub"), destination: URL(string: "https://github.com/HTsummer0908")!)
            // 2026-09-11: Point to the release repository; private access follows GitHub account permissions.
            Link(L("项目 GitHub"), destination: URL(string: "https://github.com/HTsummer0908/yinqi")!)
        }
        Section(L("设置模式")) {
            SettingToggle(L("高级设置"), isOn: $store.value.advancedSettings)
        }
        Section(L("配置导入与导出")) {
            HStack {
                SettingLabel(title: L("当前设置"))
                Spacer()
                Button(L("导入设置…"), action: importSettings)
                Button(L("导出设置…"), action: exportSettings)
            }.frame(minHeight: settingControlHeight)
            if let message = store.transferMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        Section(L("隐私与项目状态")) {
            Text(L("音频仅在本机实时分析，不录制、不保存、不上传。仅持久化应用设置。"))
            Text(L("诊断按需开启；应用不会自动检查更新或发送遥测。"))
            Text(L("开源许可证待确定；正式发布信息以项目 README 为准。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Render only the general settings category.
    private var generalSection: some View {
    Section("Yinqi") {
        // 2026-09-11: Autonyms stay recognizable regardless of current UI language.
        Picker(selection: $store.value.language) {
            Text(L("跟随系统")).tag("system")
            ForEach(AppLanguage.codes, id: \.self) { code in Text(AppLanguage.names[code]!).tag(code) }
        } label: { SettingLabel(title: L("语言")) }.frame(minHeight: settingControlHeight)
        if store.languageRestartRequired {
            HStack {
                Text(L("语言将在重启后生效")).foregroundStyle(.secondary)
                Spacer()
                Button(L("立即重启"), action: restartApplication)
            }.frame(minHeight: settingControlHeight)
        }
        // 2026-09-11: Use the persisted enable intent shared with the menu, while actions own capture lifecycle.
        SettingToggle(L("启用频谱"), isOn: Binding(get: { store.value.spectrumEnabled }, set: { enabled in
            if enabled { enableSpectrum() } else { hideSpectrum() }
        }))
        SettingToggle(L("在 Dock 中显示"), isOn: $store.value.showInDock)
        SettingToggle(L("屏幕截图时隐藏"), isOn: $store.value.hideInScreenshots)
        // 2026-09-11: Common presets explicitly dock and fill in one action, without entering edit mode.
        HStack {
            SettingLabel(title: L("快速布局"))
            Spacer()
            ForEach(["top", "bottom", "left", "right"], id: \.self) { edge in
                Button(action: { quickLayout("fill-" + edge) }) {
                    Text(["top": L("顶部铺满"), "bottom": L("底部铺满"), "left": L("左侧铺满"), "right": L("右侧铺满")][edge]!)
                        .frame(minWidth: 42)
                }
            }
        }.frame(minHeight: settingControlHeight)
        Button(L("打开运行诊断…"), action: showDiagnostics)
        if let warning = store.warning { Text(warning).foregroundStyle(.orange) }
        Button(L("恢复全部默认设置")) {
            // Preserve launch history and live capture intent when restoring preferences.
            var defaults = Settings()
            defaults.hasLaunched = store.value.hasLaunched
            defaults.spectrumEnabled = store.value.spectrumEnabled
            store.value = defaults; store.saveNow()
        }
    }
    }

    /// 2026-09-11: Separate frequency bounds from spectrum layout; preset sliders both increase reduction to the right.
    @ViewBuilder private var spectrumSection: some View {
    Section(L("频谱")) {
        Picker(selection: $store.value.channelMode) {
            Text(L("合并声道")).tag("merged")
            Text(L("左右声道")).tag("stereo")
        } label: { SettingLabel(title: L("声道")) }.frame(minHeight: settingControlHeight)
        Picker(selection: $store.value.barCount) {
            ForEach([16,32,64,128], id: \.self) { Text("\($0)").tag($0) }
        } label: { SettingLabel(title: L("柱条总数")) }.frame(minHeight: settingControlHeight)
        if store.value.channelMode == "stereo" {
            Picker(selection: $store.value.stereoOrder) {
                Text(L("同向：低→高 | 低→高")).tag("ascending")
                Text(L("低频在外侧：低→高 | 高→低")).tag("lowOutside")
                Text(L("低频在中央：高→低 | 低→高")).tag("lowInside")
            } label: { SettingLabel(title: L("频率排列")) }.frame(minHeight: settingControlHeight)
            NumericSettingRow(name: L("声道额外间隔"), value: $store.value.channelGap, range: 0...40, unit: "pt", step: 0.1, presets: [0, 4, 10, 20, 40], advanced: store.value.advancedSettings, lowLabel: L("紧"), highLabel: L("宽"))
        }
    }
    Section(L("频率范围")) {
        NumericSettingRow(name: L("最低频率"), value: $store.value.frequencyMin, range: 20...(store.value.frequencyMax-1), unit: "Hz", step: 1, presets: [20, 50, 100, 200, 500], advanced: store.value.advancedSettings, lowLabel: L("不缩减"), highLabel: L("多"), presetName: L("低频范围缩减"))
        NumericSettingRow(name: L("最高频率"), value: $store.value.frequencyMax, range: (store.value.frequencyMin+1)...20000, unit: "Hz", step: 1, presets: [20000, 16000, 12000, 8000, 4000], advanced: store.value.advancedSettings, lowLabel: L("不缩减"), highLabel: L("多"), presetName: L("高频范围缩减"))
    }
    }

    /// Render only the animation settings category.
    private var animationSection: some View {
    Section(L("动画")) {
        // 2026-09-11: Neutral backend names expose a user choice without unverified power/performance claims.
        Picker(selection: $store.value.rendererBackend) {
            Text("Core Animation").tag("coreAnimation")
            Text("Metal").tag("metal")
        } label: { SettingLabel(title: L("渲染方式")) }.frame(minHeight: settingControlHeight)
        if store.rendererRestartRequired {
            HStack {
                Text(L("渲染方式将在重启后生效")).foregroundStyle(.secondary)
                Spacer()
                Button(L("立即重启"), action: restartApplication)
            }.frame(minHeight: settingControlHeight)
        }
        SettingToggle(L("无限制（跟随屏幕最高刷新率）"), isOn: unlimitedBinding)
        if store.value.frameRate != 0 {
            if store.value.advancedSettings { SettingToggle(L("自定义帧率"), isOn: customFrameRateBinding) }
            if store.value.customFrameRate && store.value.advancedSettings {
                NumericSettingRow(name: L("目标帧率"), value: frameRateBinding, range: 10...1000, unit: "FPS", step: 1)
            } else {
                HStack {
                    SettingLabel(title: L("目标帧率"))
                    if !Settings.frameRatePresets.contains(store.value.frameRate) {
                        SettingInfo(text: L("当前自定义帧率已保留；选择预设后替换。"))
                    }
                    Spacer()
                    ForEach(Settings.frameRatePresets, id: \.self) { rate in
                        Button("\(rate)") { store.value.frameRate = rate; store.value.customFrameRate = false }
                            .buttonStyle(.bordered)
                            .tint(store.value.frameRate == rate ? Color.accentColor : Color.secondary)
                    }
                }.frame(minHeight: settingControlHeight)
            }
        }
        NumericSettingRow(name: L("音量灵敏度"), value: $store.value.sensitivityDB, range: -24...24, unit: "dB", step: 0.1, presets: [-24, -12, 0, 12, 24], advanced: store.value.advancedSettings, lowLabel: L("弱"), highLabel: L("强"))
        NumericSettingRow(name: L("回落时间"), value: $store.value.releaseMs, range: 80...500, unit: "ms", step: 1, presets: [500, 350, 250, 150, 80], advanced: store.value.advancedSettings, lowLabel: L("慢"), highLabel: L("快"))
    }
    }

    /// Render only the appearance settings category.
    @ViewBuilder private var appearanceSection: some View {
    Section(L("主题预设")) {
        if let preset = store.value.selectedThemePreset {
            HStack {
                Text(store.value.isThemePresetCustomized
                    ? L("自定义 · 基于 %@", L(preset.nameKey))
                    : L("已应用：%@", L(preset.nameKey)))
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if store.value.isThemePresetCustomized {
                    Button(L("恢复此预设")) { store.value = store.value.restoringThemePreset() }
                }
            }.frame(minHeight: settingControlHeight)
        } else {
            Text(L("选择一个预设作为起点，之后仍可修改下方所有设置。"))
                .font(.callout).foregroundStyle(.secondary)
        }
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(ThemePreset.all) { preset in
                Button { store.value = store.value.applyingThemePreset(preset) } label: {
                    ThemePresetCard(
                        preset: preset,
                        selected: store.value.themePresetID == preset.id,
                        customized: store.value.themePresetID == preset.id && store.value.isThemePresetCustomized
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("应用主题：%@", L(preset.nameKey)))
            }
        }.padding(.vertical, 2)
    }
    Section(L("外观")) {
        Picker(selection: $store.value.style) {
            Text(L("极简纯色")).tag("solid"); Text(L("渐变")).tag("gradient"); Text(L("复古 LED")).tag("led")
        } label: { SettingLabel(title: L("风格")) }.frame(minHeight: settingControlHeight)
        if store.value.style == "gradient" {
            Picker(selection: $store.value.gradientDirection) {
                Text(L("从左到右")).tag("horizontal")
                Text(L("从下到上")).tag("vertical")
            } label: { SettingLabel(title: L("渐变方向")) }.frame(minHeight: settingControlHeight)
        }
        if store.value.style == "gradient" {
            ColorPicker(L("渐变起点"), selection: colorBinding(1), supportsOpacity: false).frame(minHeight: settingControlHeight)
            ColorPicker(L("渐变终点"), selection: colorBinding(2), supportsOpacity: false).frame(minHeight: settingControlHeight)
        } else {
            ColorPicker(L("主色 / LED"), selection: colorBinding(0), supportsOpacity: false).frame(minHeight: settingControlHeight)
        }
        NumericSettingRow(name: L("柱间距"), value: $store.value.gap, range: 0...8, unit: "pt", step: 0.1, presets: [0, 1, 2, 4, 8], advanced: store.value.advancedSettings, lowLabel: L("紧"), highLabel: L("宽"))
        NumericSettingRow(name: L("柱顶圆角"), value: $store.value.cornerRadius, range: 0...8, unit: "pt", step: 0.1, presets: [0, 1, 2, 4, 8], advanced: store.value.advancedSettings, lowLabel: L("直"), highLabel: L("圆"))
        SettingToggle(L("基部也应用圆角"), isOn: $store.value.roundBase)
        NumericSettingRow(name: L("柱条透明度"), value: percentBinding(\Settings.barOpacity), range: 10...100, unit: "%", step: 1, presets: [10, 30, 50, 75, 100], advanced: store.value.advancedSettings, lowLabel: L("淡"), highLabel: L("浓"))
    }
    Section(L("峰值标记")) {
        SettingToggle(L("峰值标记"), isOn: $store.value.peakEnabled)
        if store.value.peakEnabled {
            Picker(selection: $store.value.peakStyle) {
                Text(L("细横线")).tag("line"); Text(L("小砖块")).tag("brick"); Text(L("圆角砖块")).tag("rounded")
            } label: { SettingLabel(title: L("标记样式")) }.frame(minHeight: settingControlHeight)
            if store.value.peakStyle != "line" {
                NumericSettingRow(name: L("标记厚度"), value: $store.value.peakThickness, range: 1...12, unit: "pt", step: 0.5, presets: [1, 2, 3, 6, 12], advanced: store.value.advancedSettings, lowLabel: L("细"), highLabel: L("粗"))
            }
            NumericSettingRow(name: L("下落速度"), value: $store.value.peakFallSpeed, range: 1...200, unit: "%/s", step: 1, presets: [5, 10, 20, 30, 40], advanced: store.value.advancedSettings, lowLabel: L("慢"), highLabel: L("快"))
            SettingToggle(L("自定义标记颜色"), isOn: $store.value.peakCustomColor)
            if store.value.peakCustomColor { ColorPicker(L("标记颜色"), selection: peakColorBinding, supportsOpacity: false).frame(minHeight: settingControlHeight) }
        }
    }
    }

    /// Render only the placement settings category.
    private var placementSection: some View {
    Section(L("位置")) {
        Picker(selection: placementBinding) {
            Text(L("底部")).tag("bottom"); Text(L("顶部")).tag("top"); Text(L("左侧")).tag("left"); Text(L("右侧")).tag("right"); Text(L("自由")).tag("free")
        } label: { SettingLabel(title: L("位置")) }.frame(minHeight: settingControlHeight)
        Picker(selection: $store.value.growthDirection) {
            if store.value.isVertical {
                Text(L("向右")).tag("right"); Text(L("向左")).tag("left")
            } else {
                Text(L("向上")).tag("up"); Text(L("向下")).tag("down")
            }
        } label: { SettingLabel(title: L("生长方向")) }.frame(minHeight: settingControlHeight)
        NumericSettingRow(name: L("边缘间距"), value: $store.value.edgeInset, range: 0...120, unit: "pt", step: 1, presets: [0, 8, 24, 60, 120], advanced: store.value.advancedSettings, lowLabel: L("近"), highLabel: L("远"))
        SettingToggle(L("调整位置与尺寸"), isOn: Binding(get: { store.isEditing }, set: { enabled in
            if enabled != store.isEditing { editSpectrum() }
        }))
    }
    }

    /// 2026-09-11: Persist the optional marker palette as portable RGB.
    private var peakColorBinding: Binding<Color> {
        Binding(get: {
            let c = store.value.peakColor
            return Color(red: c[0], green: c[1], blue: c[2])
        }, set: { color in
            guard let c = NSColor(color).usingColorSpace(.deviceRGB) else { return }
            store.value.peakColor = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
        })
    }

    /// 2026-09-11: Zero encodes screen-following mode; switching back restores the prior finite rate.
    private var unlimitedBinding: Binding<Bool> {
        Binding(get: { store.value.frameRate == 0 }, set: { store.value = store.value.settingUnlimited($0) })
    }

    /// 2026-09-11: Mutually exclusive preset/custom controls share one persisted scheduling setting.
    private var customFrameRateBinding: Binding<Bool> {
        Binding(get: { store.value.customFrameRate }, set: { store.value = store.value.settingCustomFrameRate($0) })
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
    var presets: [Double] = []
    var advanced = true
    var lowLabel = L("小")
    var highLabel = L("大")
    /// 2026-09-11: Presets describe reduction; exact numeric editing retains frequency-bound terminology.
    var presetName: String? = nil
    @StateObject private var input = NumericDraft()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !presets.isEmpty && advanced {
                SettingToggle(L("自定义%@", name), isOn: $input.custom)
                    .onChange(of: input.custom) { _, _ in focused = false }
            }
            if presets.isEmpty || (advanced && input.custom) {
            HStack(spacing: 10) {
                // 2026-09-11: Explicit columns keep every slider and numeric field aligned across categories.
                SettingLabel(title: name).frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
                // 2026-09-11: Flexible label space pushes the equal-width control columns to the trailing edge.
                Slider(value: sliderBinding, in: range).frame(width: 180).accessibilityLabel(name)
                TextField(name, text: $input.text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder).frame(width: 76)
                    .multilineTextAlignment(.trailing).focused($focused)
                    .onSubmit { commit() }
                    .onExitCommand { sync(); focused = false }
                Text(unit).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
            }.frame(minHeight: settingControlHeight)
            } else {
                HStack {
                    SettingLabel(title: presetName ?? name).frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 0) {
                        // 2026-09-11: Exactly five native stops provide readable ticks without the old dense numeric-step rendering.
                        // 2026-09-11: Grouped Form reserves an implicit label column unless labels are hidden.
                        // Give the track and captions the same explicit width to prevent the left caption drifting.
                        Slider(value: presetBinding, in: 0...Double(presets.count-1), step: 1)
                            .labelsHidden().frame(width: 306)
                            .accessibilityLabel(presetName ?? name)
                        HStack {
                            Text(L(lowLabel))
                            Spacer()
                            if name == L("音量灵敏度") { Text(L("中")); Spacer() }
                            Text(L(highLabel))
                        }.font(.caption).foregroundStyle(.secondary).frame(width: 306)
                    }.frame(width: 306)
                    .help(L("拖动选择预设；未拖动时保留当前数值。高级设置可精确调整。"))
                }.frame(minHeight: settingControlHeight)
            }
            if input.invalid { Text(L("请输入 %@–%@ 范围内的数字", String(describing: range.lowerBound.formatted()), String(describing: range.upperBound.formatted())))
                .font(.caption).foregroundStyle(.red) }
        }
        .onAppear { sync(); input.custom = !presets.contains(where: { abs($0-value)<0.0001 }) }
        .onChange(of: value) { _, _ in sync() }
        .onChange(of: focused) { _, active in if !active { commit() } }
    }

    /// 2026-09-11: Reading a nearby stop never mutates a custom value; only user movement selects a valid preset.
    private var presetBinding: Binding<Double> {
        Binding(get: {
            Double(presets.indices.min(by: { abs(presets[$0]-value) < abs(presets[$1]-value) }) ?? 0)
        }, set: { proposed in
            let requested = Int(proposed.rounded())
            let valid = presets.indices.filter { range.contains(presets[$0]) }
            guard let index = valid.min(by: { abs($0-requested) < abs($1-requested) }) else { return }
            value = presets[index]
        })
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
    @Published var custom = false
}


/// Category selection is transient UI state and never changes audio or saved user preferences.
private final class SettingsNavigation: ObservableObject {
    @Published var category = SettingsCategory.general
}

/// 2026-09-14: A compact native card previews each built-in palette without introducing image assets.
private struct ThemePresetCard: View {
    let preset: ThemePreset
    let selected: Bool
    let customized: Bool

    private var first: Color {
        let c = preset.values.style == "gradient" ? preset.values.gradientColors[0] : preset.values.primaryColor
        return Color(red: c[0], green: c[1], blue: c[2])
    }
    private var last: Color {
        let c = preset.values.style == "gradient" ? preset.values.gradientColors[1] : preset.values.primaryColor
        return Color(red: c[0], green: c[1], blue: c[2])
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array([9,18,13,24,16,21,11].enumerated()), id: \.offset) { index, height in
                    RoundedRectangle(cornerRadius: preset.values.style == "led" ? 1 : 2)
                        .fill(LinearGradient(colors: [first, last], startPoint: .bottom, endPoint: .top))
                        .frame(width: 4, height: CGFloat(height))
                        // 2026-09-14: LED cards use a dotted mask to suggest the production segmented renderer.
                        .mask(preset.values.style == "led"
                            ? AnyView(VStack(spacing: 2) {
                                ForEach(0..<4, id: \.self) { _ in Rectangle().frame(height: 4) }
                            })
                            : AnyView(Rectangle()))
                        .opacity(index == 0 || index == 6 ? 0.72 : 1)
                }
            }.frame(width: 42, height: 26, alignment: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(preset.nameKey)).font(.callout).fontWeight(.semibold).lineLimit(1)
                Text(customized ? L("已修改") : L(preset.subtitleKey))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if selected { Image(systemName: customized ? "slider.horizontal.3" : "checkmark.circle.fill").foregroundStyle(first) }
        }
        .padding(10).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(first.opacity(selected ? 0.12 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? first.opacity(0.9) : Color.secondary.opacity(0.2), lineWidth: selected ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
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

/// 2026-09-11: Keep explanatory text beside the control name, available through native hover help and accessibility.
private struct SettingLabel: View {
    let title: String
    private var hint: String? {
        switch title {
        case L("语言"): return L("默认跟随系统语言；手动更改后重启生效。")
        case L("当前设置"): return L("使用 JSON 文件备份或分享配置；渲染方式变更需重启，保留本机频谱启停状态。")
        case L("渲染方式"): return L("更改后需重启应用，释放旧进程的渲染资源。重启前继续使用当前方式。")
        case L("快速布局"): return L("一键沿所选屏幕边缘铺满，保留当前厚度及边缘间距。")
        case L("调整位置与尺寸"): return L("开启后可拖动悬浮窗和边框；关闭后锁定并恢复鼠标穿透。")
        case L("峰值标记"): return L("柱顶推高标记，随后缓慢落回柱顶。")
        case L("基部也应用圆角"): return L("基部是贴边的一端；关闭时仅柱顶圆角。")
        case L("柱间距"): return L("零间距连接相邻柱身，圆角处仍保留弧线。")
        case L("屏幕截图时隐藏"): return L("桌面上仍然显示，截图时排除悬浮内容。")
        case L("在 Dock 中显示"): return L("关闭后仍可从菜单栏打开设置。关闭设置窗口不会停止频谱。")
        case L("启用频谱"): return L("只分析本机系统播放音频，不保存或上传声音。")
        case L("高级设置"): return L("提供更加细致的数值调整")
        case L("声道"), L("频率排列"): return L("左右声道各占一半柱数；水平时左、右排列，侧边时上、下排列。")
        case L("低频范围缩减"): return L("向右拖动，减少显示的低频范围。")
        case L("高频范围缩减"): return L("向右拖动，减少显示的高频范围。")
        case L("最低频率"), L("最高频率"): return L("设置频谱显示的频率边界。上限受采样率限制，窄低频柱共享 FFT 分辨率。")
        case L("目标帧率"), L("无限制（跟随屏幕最高刷新率）"): return L("实际帧率受屏幕和系统调度影响；静音淡出后暂停绘制。")
        default: return nil
        }
    }
    var body: some View {
        HStack(spacing: 5) {
            Text(L(title))
            if let hint {
                SettingInfo(text: hint).accessibilityLabel(title + L("说明：") + hint)
            }
        }
    }
}

/// 2026-09-11: Share compact content sizing; grouped Form adds its own vertical row insets.
private struct SettingToggle: View {
    let title: String
    @Binding var isOn: Bool
    /// 2026-09-11: Preserve the existing setting binding while sharing row sizing and help labels.
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; self._isOn = isOn }
    var body: some View {
        Toggle(isOn: $isOn) { SettingLabel(title: title) }.frame(minHeight: settingControlHeight)
    }
}

/// 2026-09-11: Use 28 pt for control content, not the whole row; 44 pt plus Form insets made settings too sparse.
private let settingControlHeight: CGFloat = 28

/// 2026-09-11: Replace system-delayed info help with a cancellable 800 ms hover presentation.
private struct SettingInfo: View {
    let text: String
    @StateObject private var hover = InfoHoverState()

    var body: some View {
        Image(systemName: "info.circle")
            .font(.caption).foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .accessibilityLabel(text)
            .onHover { inside in
                hover.hovering = inside
                if !inside { hover.presented = false }
            }
            .task(id: hover.hovering) {
                // 2026-09-11: SwiftUI cancels this task on hover exit or view removal; no timer runs while idle.
                guard hover.hovering else { return }
                do { try await Task.sleep(for: .milliseconds(800)) }
                catch { return }
                guard !Task.isCancelled, hover.hovering else { return }
                hover.presented = true
            }
            .popover(isPresented: $hover.presented, arrowEdge: .bottom) {
                Text(text).font(.callout).padding(12).frame(maxWidth: 280)
                    .fixedSize(horizontal: false, vertical: true)
            }
    }
}

/// 2026-09-11: Keep hover state compatible with the project's command-line SwiftUI toolchain.
private final class InfoHoverState: ObservableObject {
    @Published var hovering = false
    @Published var presented = false
}
