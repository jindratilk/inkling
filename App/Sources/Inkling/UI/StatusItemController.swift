import AppKit
import Combine
import SwiftUI

/// The menu bar presence: a tiny ink-drop "i" that hints at what's going on.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()
    private let actions: MenuActions
    private var hosting: NSHostingController<MenuBarView>?

    init(actions: MenuActions) {
        self.actions = actions
        super.init()
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: MenuBarView(actions: actions, close: { [weak self] in self?.popover.performClose(nil) }))
        // We size the popover ourselves; letting it follow SwiftUI live made it
        // grow upward past the top of the screen.
        host.sizingOptions = []
        popover.contentViewController = host
        hosting = host

        if let button = item.button {
            button.image = Self.icon(state: .normal)
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Inkling")
        }

        let state = AppState.shared
        let prefs = Preferences.shared
        Publishers.Merge(state.objectWillChange, prefs.objectWillChange)
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] in self?.refreshIcon() }
            .store(in: &bag)
    }

    func show() {
        guard let button = item.button, !popover.isShown else { return }
        if let hosting {
            let size = hosting.sizeThatFits(in: CGSize(width: 344, height: 2000))
            popover.contentSize = CGSize(width: 344, height: ceil(size.height))
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    private func refreshIcon() {
        let state = AppState.shared
        let s: IconState
        switch state.status(Preferences.shared) {
        case .needsPermission, .off, .paused, .excluded: s = .muted
        case .checking where state.issueCount > 0: s = .issues
        default: s = .normal
        }
        item.button?.image = Self.icon(state: s)
        item.button?.appearsDisabled = s == .muted
    }

    enum IconState { case normal, issues, muted }

    /// Drawn in code so it's crisp at any scale and adapts as a template image.
    static func icon(state: IconState) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // ink drop (the dot of the i)
            let drop = NSBezierPath()
            let cx: CGFloat = 8.5
            drop.move(to: NSPoint(x: cx, y: 1.2))
            drop.curve(to: NSPoint(x: cx + 2.6, y: 5.6), controlPoint1: NSPoint(x: cx + 0.4, y: 2.6), controlPoint2: NSPoint(x: cx + 2.6, y: 4.0))
            drop.appendArc(withCenter: NSPoint(x: cx, y: 5.6), radius: 2.6, startAngle: 0, endAngle: 180, clockwise: false)
            drop.curve(to: NSPoint(x: cx, y: 1.2), controlPoint1: NSPoint(x: cx - 2.6, y: 4.0), controlPoint2: NSPoint(x: cx - 0.4, y: 2.6))
            drop.close()
            drop.fill()

            // stem
            NSBezierPath(roundedRect: NSRect(x: cx - 1.6, y: 9.4, width: 3.2, height: 4.6), xRadius: 1.6, yRadius: 1.6).fill()

            // squiggle
            let wave = NSBezierPath()
            wave.lineWidth = 1.35
            wave.lineCapStyle = .round
            var x: CGFloat = 2.6
            wave.move(to: NSPoint(x: x, y: 16.2))
            while x <= 14.6 {
                wave.line(to: NSPoint(x: x, y: 16.2 + sin((x - 2.6) / 4.0 * 2 * .pi) * 0.9))
                x += 0.5
            }
            wave.stroke()

            if state == .issues {
                NSBezierPath(ovalIn: NSRect(x: 13.2, y: 1.6, width: 4.4, height: 4.4)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuActions {
    var openSettings: (SettingsPane) -> Void
    var openOnboarding: () -> Void
    var toggleExclusion: (String) -> Void
    var quit: () -> Void
}
