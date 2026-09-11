import AppKit
import SwiftUI

/// Three independent state axes prevent editing, hiding, and silence from overriding one another.
enum PresentationMode { case hidden, locked, editing }

/// Coordinates UI lifecycle on AppKit's main thread; capture and FFT remain on their serial worker.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let capture = AudioCaptureService()
    private let store = SettingsStore()
    private var overlay: OverlayWindowController?
    private var diagnostics: NSWindow!
    private var settingsWindow: NSWindow?
    private var text: NSTextView!
    private var statusItem: NSMenuItem!
    private var editItem: NSMenuItem!
    private var mode = PresentationMode.hidden
    private var suspended = Set<String>()
    private var observers = [NSObjectProtocol]()
    private var renderTimer: DispatchSourceTimer?
    private var lastPaused = true
    private var lastStatus = CaptureStatus(message:"尚未启用系统音频")

    /// Launch with a privacy explanation and explicit enable action, retaining a menu control entry.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 2026-09-11: Dock visibility is a saved preference, independent of install location.
        applyActivationPolicy(store.value)
        let applicationMenu = NSMenu()
        let root = NSMenuItem(); let actions = NSMenu()
        add("设置…", #selector(showSettings), to: actions).keyEquivalent = ","
        add("运行诊断…", #selector(showDiagnostics), to: actions)
        add("退出 Yinqi", #selector(quit), to: actions).keyEquivalent = "q"
        root.submenu = actions; applicationMenu.addItem(root); NSApp.mainMenu = applicationMenu
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        // 2026-09-11: Replace the text glyph with a template so AppKit handles menu-bar contrast and highlighted states.
        if let url = Bundle.main.url(forResource: "YinqiMenuTemplate", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 20, height: 18)
            image.isTemplate = true
            item.button?.image = image
            item.button?.title = ""
            item.button?.toolTip = "音栖 Yinqi"
        } else {
            item.button?.title = "▥"
        }
        let menu = NSMenu()
        statusItem = NSMenuItem(title:"尚未启用",action:nil,keyEquivalent:""); menu.addItem(statusItem)
        add("显示 / 启用频谱",#selector(enable),to:menu)
        add("隐藏并停止采集",#selector(hide),to:menu)
        editItem = add("调整位置与尺寸",#selector(toggleEditing),to:menu)
        add("放到底部",#selector(bottom),to:menu)
        add("放到顶部",#selector(top),to:menu)
        add("放到左侧",#selector(left),to:menu)
        add("放到右侧",#selector(right),to:menu)
        add("重置到当前可见屏幕",#selector(resetPosition),to:menu)
        menu.addItem(.separator())
        add("设置…",#selector(showSettings),to:menu)
        add("诊断…",#selector(showDiagnostics),to:menu)
        add("重新尝试音频采集",#selector(retry),to:menu)
        add("退出 Yinqi",#selector(quit),to:menu)
        item.menu = menu
        do {
            overlay = try OverlayWindowController()
            overlay?.apply(store.value)
            overlay?.renderer.frameProvider = { [weak self] in self?.capture.frames.snapshot() }
            overlay?.onQuickAction = { [weak self] action in self?.quickLayout(action) }
            overlay?.onFrameChanged = { [weak self] frame,snap in self?.saveFrame(frame,snap:snap) }
        } catch { lastStatus = CaptureStatus(message:"Metal 初始化失败：\(error.localizedDescription)") }
        capture.configure(store.value)
        capture.onStatus = { [weak self] status in self?.lastStatus = status; self?.updateDiagnostics() }
        store.onChange = { [weak self] value in
            guard let self else { return }
            self.applyActivationPolicy(value)
            self.capture.configure(value); self.overlay?.apply(value); self.refreshRenderer()
        }
        observeSleep()
        // 2026-09-11: Only first launch opens settings; diagnostics are always explicitly requested.
        let firstLaunch = !store.value.hasLaunched
        store.value.hasLaunched = true; store.saveNow()
        if store.value.spectrumEnabled { enable() }
        if firstLaunch { showSettings() }
        updateDiagnostics()
    }

    /// Build a normal focusable window with direct controls; only the overlay remains nonactivating.
    private func makeDiagnostics() {
        diagnostics = NSWindow(contentRect:NSRect(x:200,y:220,width:700,height:360),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        diagnostics.title = "Yinqi — 运行诊断"
        diagnostics.isReleasedWhenClosed = false
        let content = NSView(frame:diagnostics.contentView!.bounds)
        text = NSTextView(frame:NSRect(x:0,y:48,width:700,height:312))
        text.autoresizingMask = [.width,.height]; text.isEditable = false
        text.font = .monospacedSystemFont(ofSize:13,weight:.regular)
        text.textContainerInset = NSSize(width:16,height:16); content.addSubview(text)
        for (index,entry) in [("启用系统音频",#selector(enable)),("停止",#selector(hide)),("调整 / 锁定",#selector(toggleEditing)),("设置",#selector(showSettings)),("退出",#selector(quit))].enumerated() {
            let button = NSButton(title:entry.0,target:self,action:entry.1)
            button.frame = NSRect(x:16+index*132,y:10,width:124,height:30); content.addSubview(button)
        }
        diagnostics.contentView = content
    }

    /// Explicit targets keep the accessory app's menu independent of the current responder chain.
    @discardableResult private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title:title,action:action,keyEquivalent:""); entry.target = self; menu.addItem(entry); return entry
    }

    /// User display intent survives sleep but never overrides an explicit hidden state.
    @objc private func enable() {
        guard let overlay else { showDiagnostics(); return }
        if mode == .hidden { mode = .locked }
        if !store.value.spectrumEnabled { store.value.spectrumEnabled = true }
        overlay.show()
        if suspended.isEmpty { capture.start(); startRenderPolling() }
        updateDiagnostics()
    }

    /// Stop both capture and high-frequency UI/GPU work when the user hides the overlay.
    @objc private func hide() {
        mode = .hidden; overlay?.editing = false
        if store.value.spectrumEnabled { store.value.spectrumEnabled = false }
        overlay?.hide(); capture.stop(); stopRenderPolling()
        editItem.title = "调整位置与尺寸"; updateDiagnostics()
    }

    /// Manual retries first dispose of all previous HAL resources, then honor current user intent.
    @objc private func retry() {
        if mode == .hidden { enable(); return }
        capture.stop { [weak self] in guard let self, self.mode != .hidden, self.suspended.isEmpty else { return }; self.capture.start() }
    }

    /// Edit mode leaves a visible border even with no audio and returns to click-through on completion.
    @objc private func toggleEditing() {
        if mode == .hidden { enable() }
        mode = mode == .editing ? .locked : .editing
        overlay?.editing = mode == .editing
        editItem.title = mode == .editing ? "完成调整" : "调整位置与尺寸"
        if mode == .locked { store.saveNow() }
        refreshRenderer()
    }

    /// Bottom placement resets the natural growth direction while later manual direction changes remain possible.
    @objc private func bottom() { store.value = store.value.placing(at: "bottom") }

    /// Top placement grows downward from the screen's safe top edge.
    @objc private func top() { store.value = store.value.placing(at: "top") }

    /// Side placement rotates the strip and grows towards the screen interior.
    @objc private func left() { store.value = store.value.placing(at: "left") }

    /// Right-side placement preserves thickness while rotating the frequency axis vertically.
    @objc private func right() { store.value = store.value.placing(at: "right") }

    /// 2026-09-11: Settings and overlay toolbar share one saved layout action path.
    private func quickLayout(_ action: String) {
        if action == "lock" { if mode == .editing { toggleEditing() }; return }
        var s = store.value
        if ["top","bottom","left","right"].contains(action) { s = s.placing(at: action) }
        else if action == "fill" {
            if s.placementMode == "free" { s = s.placing(at: s.isVertical ? "left" : "bottom") }
            s.layoutMode = "fill"
        } else if action == "center", let screen = overlay?.panel.screen ?? NSScreen.main {
            s = s.centered(in: screen.visibleFrame, frame: overlay?.panel.frame ?? restoredFrame(s, safe: screen.visibleFrame))
        }
        store.value = s; store.saveNow()
    }

    /// Discard stale display hints and restore a safe default rectangle on the current main screen.
    @objc private func resetPosition() {
        var s=store.value; s.placementMode="bottom"; s.growthDirection="up"; s.width=0; s.height=96; s.layoutMode="custom"
        s.screenHint = String(describing:NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "")
        store.value=s; store.saveNow()
    }

    /// Save the final logical frame and best-effort display hint immediately after editing.
    private func saveFrame(_ frame:NSRect,snap:String?) {
        var s=store.value; s.x=frame.minX; s.y=frame.minY; s.width=frame.width; s.height=frame.height
        s.layoutMode="custom"
        s.placementMode=snap ?? "free"
        if let snap { s = s.placing(at: snap) }
        s.screenHint=String(describing:overlay?.panel.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "")
        store.value=s; store.saveNow()
    }

    /// Settings use their own normal key window without changing overlay activation policy.
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window=NSWindow(contentRect:NSRect(x:260,y:160,width:681,height:560),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            window.title="Yinqi 设置"; window.isReleasedWhenClosed=false
            // 2026-09-11: A compact default with a minimum size keeps numeric columns readable during resize.
            window.contentMinSize = NSSize(width:681,height:400)
            window.contentView=NSHostingView(rootView:SettingsView(store:store, showDiagnostics: { [weak self] in self?.showDiagnostics() }, enableSpectrum: { [weak self] in self?.enable() }, hideSpectrum: { [weak self] in self?.hide() }, editSpectrum: { [weak self] in self?.toggleEditing() }, quickLayout: { [weak self] action in self?.quickLayout(action) })); settingsWindow=window
        }
        NSApp.activate(ignoringOtherApps:true); settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// This explicitly requested diagnostics window may acquire keyboard focus.
    @objc private func showDiagnostics() {
        if diagnostics == nil { makeDiagnostics() }
        NSApp.activate(ignoringOtherApps:true); diagnostics.makeKeyAndOrderFront(nil)
        updateDiagnostics()
    }

    /// 2026-09-11: Changing Dock visibility leaves the nonactivating overlay policy unchanged.
    private func applyActivationPolicy(_ settings: Settings) {
        let policy: NSApplication.ActivationPolicy = settings.showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    /// Dock clicks reopen settings even when the overlay is the only visible window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return false
    }

    /// Closing control windows preserves the lightweight menu-bar app and capture intent.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Report real capture data and actual renderer pause state separately from the user's display intent.
    private func updateDiagnostics() {
        let f=capture.frames.snapshot()
        statusItem.title = mode == .hidden ? "已隐藏" : (f.opacity == 0 ? "无声音 / \(lastStatus.message.prefix(28))" : String(lastStatus.message.prefix(40)))
        // 2026-09-11: No diagnostic string allocation or UI refresh while its window is closed.
        guard diagnostics?.isVisible == true else { return }
        text.string="仅在本机分析系统播放音频，不保存或上传声音。\n请点击启用系统音频；拒绝后请在系统设置检查权限，再手动重试。\n\n状态：\(lastStatus.message)\n采样率：\(lastStatus.sampleRate) Hz；通道：\(lastStatus.channels)\nIO 回调：\(lastStatus.callbacks)；丢弃帧：\(lastStatus.dropped)\nRMS：\(String(format:"%.2f",lastStatus.rmsDB)) dBFS；Peak：\(lastStatus.peak)\n分析序号：\(f.sequence)；\(store.value.barCount) 柱；GPU 连续绘制暂停：\(overlay?.renderer.view.isPaused ?? true)\n频段峰值：\(f.bands.max() ?? 0)；淡出系数：\(f.opacity)\n绘制回调：\(overlay?.renderer.drawCallbacks ?? 0)；提交帧：\(overlay?.renderer.submittedFrames ?? 0)\n画布：\(overlay?.renderer.view.bounds.size ?? .zero)；窗口可见：\(overlay?.panel.isVisible ?? false)\n绘制状态：\(overlay?.renderer.lastDrawFailure ?? "无渲染器")\n\n\(store.warning ?? "窗口全屏兼容与设备恢复范围见测试报告。")"
    }

    /// 2026-09-11: A 10 Hz wake check replaces duplicate 60 Hz polling; drawing reads fresh frames directly.
    private func startRenderPolling() {
        guard renderTimer == nil else { return }
        let timer=DispatchSource.makeTimerSource(queue:.main)
        timer.schedule(deadline:.now(),repeating:.milliseconds(100),leeway:.milliseconds(2))
        timer.setEventHandler { [weak self] in self?.refreshRenderer() }
        renderTimer=timer; lastPaused=false; timer.resume()
    }

    /// Main-thread snapshots safely feed Metal; transition to silence performs one final clear.
    private func refreshRenderer() {
        guard let overlay else { return }
        let frame=capture.frames.snapshot()
        let hidden=mode == .hidden || !suspended.isEmpty
        overlay.renderer.update(frame,settings:store.value.validated(),editing:mode == .editing,hidden:hidden)
        let paused=frame.opacity <= 0 || hidden
        if paused != lastPaused {
            lastPaused=paused
            updateDiagnostics()
        }
    }

    /// Stop polling and clear the final drawable when suspended or explicitly hidden.
    private func stopRenderPolling() { renderTimer?.cancel(); renderTimer=nil; refreshRenderer() }

    /// Public workspace notifications cover display sleep, system sleep, and inactive login sessions.
    private func observeSleep() {
        let center=NSWorkspace.shared.notificationCenter
        for pair in [(NSWorkspace.willSleepNotification,NSWorkspace.didWakeNotification,"system"),
                     (NSWorkspace.screensDidSleepNotification,NSWorkspace.screensDidWakeNotification,"display"),
                     (NSWorkspace.sessionDidResignActiveNotification,NSWorkspace.sessionDidBecomeActiveNotification,"session")] {
            observers.append(center.addObserver(forName:pair.0,object:nil,queue:.main) { [weak self] _ in
                guard let self else {return}; self.suspended.insert(pair.2); self.capture.stop(); self.overlay?.hide(); self.stopRenderPolling()
            })
            observers.append(center.addObserver(forName:pair.1,object:nil,queue:.main) { [weak self] _ in
                guard let self else {return}; self.suspended.remove(pair.2)
                if self.suspended.isEmpty && self.mode != .hidden { self.enable() }
            })
        }
    }

    /// Flush settings and stop HAL resources before AppKit terminates the process.
    @objc private func quit() { NSApp.terminate(nil) }

    /// A single asynchronous termination path prevents callback context from outliving its owner.
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        mode = .hidden; stopRenderPolling(); store.saveNow()
        capture.stop { NSApp.reply(toApplicationShouldTerminate:true) }
        return .terminateLater
    }
}

let app=NSApplication.shared
let delegate=AppDelegate()
app.delegate=delegate
app.run()
