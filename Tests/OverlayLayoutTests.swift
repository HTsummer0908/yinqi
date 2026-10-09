// SPDX-License-Identifier: MPL-2.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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
        // 2026-10-09: A non-key overlay needs active-always tracking to advertise resize handles.
        let surface = overlay.panel.contentView!
        surface.updateTrackingAreas()
        assert(surface.trackingAreas.contains { $0.options.contains(.activeAlways) && $0.options.contains(.mouseMoved) && !$0.options.contains(.cursorUpdate) }, "Non-key editing needs active-always cursor tracking")
        assert(overlay.panel.acceptsMouseMovedEvents, "Editing must opt into window mouse-moved delivery")
        // 2026-10-09: Exercise the actual event handler without moving the user's hardware pointer.
        // 2026-10-09: Visible handles must work without activating the app or taking keyboard focus.
        let activeBeforeHover = NSApp.isActive
        let handles = surface.layer!.sublayers!.filter { $0.name?.hasPrefix("resize-handle-") == true }
        assert(handles.count == 8 && handles.allSatisfy { !$0.isHidden }, "Editing needs eight visible resize handles")
        let idleHandleColor = handles.first!.backgroundColor!
        let center = NSPoint(x: surface.bounds.midX, y: surface.bounds.midY)
        let hover = NSEvent.mouseEvent(with: .mouseMoved, location: center, modifierFlags: [], timestamp: 0, windowNumber: overlay.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        surface.mouseMoved(with: hover)
        assert(NSCursor.current == NSCursor.openHand, "Editor interior should advertise dragging")
        let edgeHover = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 2, y: center.y), modifierFlags: [], timestamp: 0, windowNumber: overlay.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        surface.mouseMoved(with: edgeHover)
        assert(NSCursor.current != NSCursor.openHand && NSCursor.current != NSCursor.arrow, "Edge should display a resize cursor")
        assert(handles.contains { $0.backgroundColor != idleHandleColor }, "Hover must highlight a resize handle")
        assert(NSApp.isActive == activeBeforeHover && !overlay.panel.isKeyWindow, "Hover must not activate Yinqi")
        surface.mouseExited(with: edgeHover)
        assert(NSCursor.current == NSCursor.arrow)
        // 2026-10-09: Both orientations must retain a full usable-screen rectangle after validation.
        let safe = overlay.panel.screen!.visibleFrame
        for placement in ["bottom", "right"] {
            var full = Settings().placing(at: placement)
            full.layoutMode = "custom"; full.width = safe.width; full.height = safe.height
            full.x = safe.minX; full.y = safe.minY
            assert(restoredFrame(full.validated(), safe: safe).size == safe.size, "Full-screen dimensions must survive settings validation")
        }
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
        assert(!overlay.panel.acceptsMouseMovedEvents, "Locked mode must stop mouse-moved delivery")
        assert(handles.allSatisfy { $0.isHidden }, "Locked mode must hide resize handles")
        assert(surface.trackingAreas.isEmpty, "Locked mode must remove editing tracking")
        var side = Settings().placing(at:"right"); side.layoutMode="fill"
        overlay.apply(side)
        assert(overlay.panel.frame.height == overlay.panel.screen!.visibleFrame.height)
        assert(overlay.renderer.surfaceView.frame.size == overlay.panel.frame.size)
        overlay.editing = true
        overlay.hide()
        assert(!toolbar.isVisible)
        print("PASS: overlay / host / Metal dimensions and window lifecycle")
    }
}
