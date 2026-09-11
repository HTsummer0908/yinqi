import AppKit
import MetalKit

/// Reproduce the actual panel/view hierarchy without requesting audio capture.
@main struct OverlayLayoutTests {
    /// A configured visible-sized panel must have a matching nonzero Metal view and drawable.
    static func main() throws {
        _ = NSApplication.shared
        let overlay = try OverlayWindowController()
        overlay.apply(Settings())
        let view = overlay.renderer.surfaceView as! MTKView
        assert(overlay.panel.contentView!.wantsLayer, "Metal host must participate in layer-backed window composition")
        print("panel=\(overlay.panel.frame) content=\(overlay.panel.contentView!.frame) metal=\(view.frame) drawable=\(view.drawableSize)")
        assert(view.bounds.width > 0 && view.bounds.height > 0, "Metal view must not remain zero sized")
        assert(view.frame.size == overlay.panel.contentView!.bounds.size, "Metal view must fill its host")
        assert(view.drawableSize.width > 0 && view.drawableSize.height > 0)
        assert(view.layer!.contentsScale > 0, "A zero CAMetalLayer contentsScale makes submitted frames invisible")
        overlay.panel.title = "Yinqi 独立渲染测试（合成测试数据）"
        overlay.show()
        overlay.renderer.update(SpectrumFrame(bands: [], rmsDB: -160, timestamp: 0, sequence: 0, opacity: 0), settings: Settings(), editing: false, hidden: false)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let frame = SpectrumFrame(bands: [Float](repeating: 0.8, count: 64), rmsDB: -10, timestamp: 1, sequence: 1)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            overlay.renderer.update(frame, settings: Settings(), editing: false, hidden: false)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        timer.invalidate()
        print("callbacks=\(overlay.renderer.drawCallbacks) submitted=\(overlay.renderer.submittedFrames) failure=\(overlay.renderer.lastDrawFailure)")
        assert(overlay.renderer.submittedFrames > 5, "Active overlay must submit Metal frames")
        print("storeAction=\(String(describing: view.currentRenderPassDescriptor?.colorAttachments[0].storeAction.rawValue)) layer=\(String(describing:view.layer))")
        // 2026-09-11: Editing controls must not survive hiding or locked click-through mode.
        overlay.editing = true
        let toolbar = NSApp.windows.first { $0.title == "Yinqi 布局工具" }!
        assert(toolbar.isVisible && !toolbar.canBecomeKey && !overlay.panel.ignoresMouseEvents)
        let buttons = (toolbar.contentView as! NSStackView).arrangedSubviews.compactMap { $0 as? NSButton }
        assert(buttons.count == 7)
        var action = ""
        overlay.onQuickAction = { action = $0 }
        buttons.last!.performClick(nil)
        assert(action == "lock")
        overlay.editing = false
        assert(!toolbar.isVisible && overlay.panel.ignoresMouseEvents)
        var side = Settings().placing(at:"right"); side.layoutMode="fill"
        overlay.apply(side)
        assert(overlay.panel.frame.height == overlay.panel.screen!.visibleFrame.height)
        assert(overlay.renderer.surfaceView.frame.size == overlay.panel.frame.size)
        overlay.editing = true
        overlay.hide()
        assert(!toolbar.isVisible)
        print("PASS: overlay / host / Metal dimensions and active submissions")
    }
}
