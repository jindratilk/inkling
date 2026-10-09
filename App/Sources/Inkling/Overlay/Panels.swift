import AppKit
import SwiftUI

/// Transparent, click-through window that floats over other apps (underlines).
final class ClickThroughPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Interactive floating panel that never steals keyboard focus from the app
/// you're typing in. Keeps a chosen edge pinned while SwiftUI resizes it.
final class FloatingPanel: NSPanel {
    enum Anchor {
        case top(CGFloat)
        case bottom(CGFloat)
    }

    var anchor: Anchor?
    var anchorX: CGFloat?
    /// Keep the whole panel inside this rect (screen-visible area, shadow padding allowed).
    var limits: CGRect?
    /// Transparent margin (shadow room) around the real content.
    var margin: CGFloat = 0

    /// The visible, interactive part of the panel in screen coordinates.
    var contentRect: CGRect { frame.insetBy(dx: margin, dy: margin) }

    /// Let clicks in the transparent margin fall through to the app underneath.
    func updatePassthrough(_ p: CGPoint) {
        guard isVisible else { return }
        let ignore = !contentRect.contains(p)
        if ignoresMouseEvents != ignore { ignoresMouseEvents = ignore }
    }

    init(level: NSWindow.Level = .popUpMenu) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func pinned(_ rect: NSRect) -> NSRect {
        var r = rect
        switch anchor {
        case let .top(y): r.origin.y = y - r.height
        case let .bottom(y): r.origin.y = y
        case nil: break
        }
        if let x = anchorX { r.origin.x = x }
        if let l = limits {
            if r.maxY > l.maxY { r.origin.y = l.maxY - r.height }
            if r.minY < l.minY { r.origin.y = l.minY }
        }
        return r
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(pinned(frameRect), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(pinned(frameRect), display: displayFlag, animate: animateFlag)
    }

    /// Host a SwiftUI view whose own size drives the panel's size.
    func host<V: View>(_ view: V) {
        let wrapped = view
            .fixedSize()
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { [weak self] size in
                self?.fit(size)
            }
        let hosting = FirstMouseHostingView(rootView: AnyView(wrapped))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        contentViewController = nil
        contentView = hosting
        // Measure up-front so callers can position before the first layout pass.
        let measure = NSHostingView(rootView: view.fixedSize())
        let size = measure.fittingSize
        if size.width > 0, size.height > 0 { fit(size) }
    }

    func fit(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let rounded = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard rounded != frame.size else { return }
        setFrame(NSRect(origin: frame.origin, size: rounded), display: true)
    }

    func fadeIn() {
        if !isVisible {
            alphaValue = 1
            orderFrontRegardless()
        }
    }

    func fadeOut(_ duration: TimeInterval = 0.14) {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            self.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if self.alphaValue == 0 {
                    self.orderOut(nil)
                    self.alphaValue = 1
                }
            }
        })
    }
}

/// Hosting view that reacts to the very first click even though our app is in the background.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Make hover effects work while another app is active.
        for area in trackingAreas where !area.options.contains(.activeAlways) {
            let options = area.options.subtracting([.activeInKeyWindow, .activeInActiveApp, .activeWhenFirstResponder]).union(.activeAlways)
            let replacement = NSTrackingArea(rect: area.rect, options: options, owner: area.owner, userInfo: area.userInfo)
            removeTrackingArea(area)
            addTrackingArea(replacement)
        }
    }
}

final class FirstMouseHostingController<Content: View>: NSViewController {
    let hosting: FirstMouseHostingView<Content>

    init(rootView: Content) {
        hosting = FirstMouseHostingView(rootView: rootView)
        hosting.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
        super.init(nibName: nil, bundle: nil)
    }

    @MainActor @preconcurrency required init?(coder: NSCoder) { fatalError() }

    override func loadView() { view = hosting }

    override func viewDidLayout() {
        super.viewDidLayout()
        preferredContentSize = hosting.fittingSize
    }
}
