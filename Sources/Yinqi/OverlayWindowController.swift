import AppKit

/// Nonactivating overlay never becomes a keyboard target, including during mouse-only editing.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns public window policy, screen restoration, and logical-point editing geometry.
final class OverlayWindowController {
    let panel: OverlayPanel
    let renderer: SpectrumRenderer
    private let surface: EditingSurface
    var onQuickAction: ((String) -> Void)?
    private let toolbar = EditingToolbar()
    var onFrameChanged: ((NSRect, String?) -> Void)?
    private var screenObserver: NSObjectProtocol?
    private var settings = Settings()
    var editing = false {
        didSet {
            panel.ignoresMouseEvents = !editing; surface.editing = editing; surface.needsDisplay = true
            updateToolbar()
        }
    }

    /// Retain the exact Stage A policy verified with a separate full-screen Chrome application.
    init() throws {
        renderer = try SpectrumRenderer()
        panel = OverlayPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        surface = EditingSurface(frame:.zero)
        // 2026-09-11 11:06 +08:00: A transparent non-layer-backed host can leave the Metal
        // child outside the window backing composition. Composite the whole view tree through layers.
        surface.wantsLayer = true
        surface.layer?.isOpaque = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces,.canJoinAllApplications,.fullScreenAuxiliary]
        panel.title = "Yinqi Spectrum"
        panel.isReleasedWhenClosed = false
        panel.contentView = surface
        renderer.view.frame = surface.bounds
        renderer.view.autoresizingMask = [.width,.height]
        surface.addSubview(renderer.view)
        toolbar.onAction = { [weak self] action in self?.onQuickAction?(action) }
        surface.onMove = { [weak self] in self?.updateToolbar() }
        surface.onEnd = { [weak self] frame in self?.finishDrag(frame) }
        screenObserver = NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in
            guard let self else { return }; self.apply(self.settings)
        }
    }
    deinit { if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) } }

    /// Choose a connected saved display, otherwise the existing panel display or main screen.
    func apply(_ value: Settings) {
        settings = value.validated()
        // 2026-09-11: Match LyricsX's public AppKit policy; keep desktop visibility and exclude both overlay windows.
        let sharing: NSWindow.SharingType = settings.hideInScreenshots ? .none : .readOnly
        panel.sharingType = sharing
        toolbar.panel.sharingType = sharing
        let saved = NSScreen.screens.first { String(describing:$0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "") == settings.screenHint }
        guard let screen = saved ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        panel.setFrame(restoredFrame(settings,safe:screen.visibleFrame),display:true)
        surface.vertical = settings.isVertical
        surface.needsDisplay = true
        surface.updateDrawable()
        updateToolbar()
    }

    /// Bring forward without requesting application or keyboard activation.
    func show() { panel.orderFrontRegardless(); updateToolbar() }

    /// Hiding never changes the user's saved frame or display intent.
    func hide() { panel.orderOut(nil); toolbar.panel.orderOut(nil) }

    /// Keep controls inside the visible screen and show them only while editing a visible overlay.
    private func updateToolbar() {
        guard editing, panel.isVisible, let screen = panel.screen else { toolbar.panel.orderOut(nil); return }
        let safe = screen.visibleFrame
        let width = min(336.0, safe.width), height = 38.0
        let x = min(max(panel.frame.midX-width/2, safe.minX), safe.maxX-width)
        let preferredY = panel.frame.maxY+6 <= safe.maxY-height ? panel.frame.maxY+6 : panel.frame.minY-height-6
        let y = min(max(preferredY, safe.minY), safe.maxY-height)
        toolbar.panel.setFrame(NSRect(x:x,y:y,width:width,height:height), display:true)
        toolbar.panel.orderFrontRegardless()
    }

    /// Snap only at mouse-up and clamp to the destination screen, including negative coordinates.
    private func finishDrag(_ proposed: NSRect) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        var value = settings
        value.layoutMode = "custom"
        value.placementMode = "free"; value.x = proposed.minX; value.y = proposed.minY
        value.width = proposed.width; value.height = proposed.height
        var snap: String?
        // 2026-09-11: Snap on the current axis so dragging does not unexpectedly rotate the strip.
        if settings.isVertical {
            if abs(proposed.minX-screen.visibleFrame.minX-settings.edgeInset) <= 16 { snap = "left" }
            else if abs(proposed.maxX-screen.visibleFrame.maxX+settings.edgeInset) <= 16 { snap = "right" }
        } else {
            if abs(proposed.minY-screen.visibleFrame.minY-settings.edgeInset) <= 16 { snap = "bottom" }
            else if abs(proposed.maxY-screen.visibleFrame.maxY+settings.edgeInset) <= 16 { snap = "top" }
        }
        if let snap { value = value.placing(at: snap) }
        let frame = restoredFrame(value,safe:screen.visibleFrame)
        panel.setFrame(frame,display:true)
        onFrameChanged?(frame,snap)
    }
}

/// Hit-test surface accepts mouse gestures only in editing mode; locked clicks pass at NSPanel level.
private final class EditingSurface: NSView {
    /// 2026-09-11: Rebuild cursor regions whenever editing is toggled.
    var editing = false { didSet { window?.invalidateCursorRects(for: self) } }
    var vertical = false
    var onMove: (() -> Void)?
    var onEnd: ((NSRect) -> Void)?
    private var startPoint = NSPoint.zero
    private var startFrame = NSRect.zero
    private var edges = 0

    /// Route editor gestures to the parent rather than the Metal child view.
    override func hitTest(_ point: NSPoint) -> NSView? { editing ? self : nil }

    /// 2026-09-11: Match resize cursors to the existing 8 pt drag zones, with nonoverlapping corner regions.
    override func resetCursorRects() {
        super.resetCursorRects()
        guard editing else { return }
        let w = bounds.width, h = bounds.height, edge: CGFloat = 8
        guard w >= edge * 2, h >= edge * 2 else { return }
        let regions: [(NSRect, NSCursor.FrameResizePosition)] = [
            (NSRect(x: 0, y: edge, width: edge, height: h-2*edge), .left),
            (NSRect(x: w-edge, y: edge, width: edge, height: h-2*edge), .right),
            (NSRect(x: edge, y: 0, width: w-2*edge, height: edge), .bottom),
            (NSRect(x: edge, y: h-edge, width: w-2*edge, height: edge), .top),
            (NSRect(x: 0, y: 0, width: edge, height: edge), .bottomLeft),
            (NSRect(x: w-edge, y: 0, width: edge, height: edge), .bottomRight),
            (NSRect(x: 0, y: h-edge, width: edge, height: edge), .topLeft),
            (NSRect(x: w-edge, y: h-edge, width: edge, height: edge), .topRight)
        ]
        for (rect, position) in regions {
            addCursorRect(rect, cursor: .frameResize(position: position, directions: .all))
        }
        addCursorRect(bounds.insetBy(dx: edge, dy: edge), cursor: .openHand)
    }

    /// 2026-09-11: Keep cursor regions attached to current edges after resizing or applying quick layouts.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    /// Cache the gesture origin once so resize and drag are stable across event frequencies.
    override func mouseDown(with event: NSEvent) {
        guard editing, let window else { return }
        startPoint = NSEvent.mouseLocation; startFrame = window.frame
        let p = convert(event.locationInWindow,from:nil)
        edges = 0
        if p.x < 8 { edges |= 1 }; if p.x > bounds.width-8 { edges |= 2 }
        if p.y < 8 { edges |= 4 }; if p.y > bounds.height-8 { edges |= 8 }
    }

    /// Move the body or resize selected edges while enforcing the document's minimum dimensions.
    override func mouseDragged(with event: NSEvent) {
        guard editing, let window else { return }
        let dx = NSEvent.mouseLocation.x-startPoint.x, dy = NSEvent.mouseLocation.y-startPoint.y
        var frame = startFrame
        if edges == 0 { frame.origin.x += dx; frame.origin.y += dy }
        else {
            if edges & 1 != 0 { frame.size.width = max(vertical ? 24 : 240, startFrame.width-dx); frame.origin.x = startFrame.maxX-frame.width }
            if edges & 2 != 0 { frame.size.width = max(vertical ? 24 : 240, startFrame.width+dx) }
            if edges & 4 != 0 { frame.size.height = vertical ? max(240,startFrame.height-dy) : min(240,max(24,startFrame.height-dy)); frame.origin.y = startFrame.maxY-frame.height }
            if edges & 8 != 0 { frame.size.height = vertical ? max(240,startFrame.height+dy) : min(240,max(24,startFrame.height+dy)) }
        }
        if vertical {
            let right = frame.maxX
            frame.size.width = min(240, frame.width)
            if edges & 1 != 0 { frame.origin.x = right-frame.width }
        }
        window.setFrame(frame,display:true)
        updateDrawable(); needsDisplay = true; onMove?()
    }

    /// Persist one final constrained rectangle instead of writing on every pointer event.
    override func mouseUp(with event: NSEvent) { if let window { onEnd?(window.frame) } }

    /// Scale Metal drawable dimensions when AppKit updates the backing factor.
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateDrawable() }

    /// Metal's framebuffer is in pixels; window geometry remains in points.
    func updateDrawable() {
        if let metal = subviews.first as? MTKView {
            // 2026-09-11 11:07 +08:00: Zero-sized initialization left CAMetalLayer.contentsScale at 0.
            // Updating drawableSize alone submitted pixels but did not make them compositable on screen.
            let scale = max(1, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
            metal.layer?.contentsScale = scale
            metal.drawableSize = NSSize(width:bounds.width*scale,height:bounds.height*scale)
        }
    }

    /// Edit affordances stay visible during silence; no synthetic preview is mixed into live audio.
    override func draw(_ dirtyRect: NSRect) {
        guard editing else { return }
        NSColor.systemCyan.setStroke()
        let path = NSBezierPath(rect:bounds.insetBy(dx:1,dy:1)); path.lineWidth = 2; path.stroke()

    }
}

import MetalKit


/// 2026-09-11: Separate nonactivating edit controls remain usable even when the strip is only 24 pt thick.
private final class EditingToolbar {
    let panel: OverlayPanel
    var onAction: ((String) -> Void)?

    /// Icon buttons have descriptive accessibility labels/tooltips and never appear in locked mode.
    init() {
        panel = OverlayPanel(contentRect:NSRect(x:0,y:0,width:336,height:38),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title = "Yinqi 布局工具"
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces,.canJoinAllApplications,.fullScreenAuxiliary]
        panel.backgroundColor = .windowBackgroundColor
        let stack = NSStackView(frame:panel.contentView!.bounds)
        stack.orientation = .horizontal; stack.distribution = .fillEqually; stack.spacing = 2
        stack.autoresizingMask = [.width,.height]
        let entries = [("center","scope","居中"),("fill","arrow.up.left.and.arrow.down.right","沿当前边铺满"),
                       ("bottom","arrow.down.to.line","停靠底部"),("top","arrow.up.to.line","停靠顶部"),
                       ("left","arrow.left.to.line","停靠左侧"),("right","arrow.right.to.line","停靠右侧"),
                       ("lock","lock.fill","完成调整并锁定")]
        for (action, symbol, label) in entries {
            let button = EditingActionButton(title:label,target:nil,action:nil)
            button.image = NSImage(systemSymbolName:symbol,accessibilityDescription:label)
            button.imagePosition = .imageOnly; button.bezelStyle = .rounded
            button.toolTip = label; button.setAccessibilityLabel(label)
            button.onClick = { [weak self] in self?.onAction?(action) }
            button.target = button; button.action = #selector(EditingActionButton.invoke)
            stack.addArrangedSubview(button)
        }
        panel.contentView = stack
    }
}

/// A closure-backed button keeps toolbar actions separate from realtime and keyboard focus handling.
private final class EditingActionButton: NSButton {
    var onClick: (() -> Void)?
    /// Dispatch only the explicitly clicked layout action.
    @objc func invoke() { onClick?() }
}
