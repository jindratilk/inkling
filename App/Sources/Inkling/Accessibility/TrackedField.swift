import AppKit
import ApplicationServices

/// The text field the user is currently typing in, in some other app.
final class TrackedField {
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?
    let appName: String
    let appIcon: NSImage?
    let role: String
    var text: String
    var selection: NSRange?
    /// Scroll areas / web areas above the field — used to clip underlines to what's visible.
    let clipAncestors: [AXUIElement]

    init(element: AXUIElement, app: NSRunningApplication, text: String) {
        self.element = element
        pid = app.processIdentifier
        bundleID = app.bundleIdentifier
        appName = app.localizedName ?? "App"
        appIcon = app.icon
        role = element.role ?? ""
        self.text = text
        selection = element.selectedRange

        var ancestors: [AXUIElement] = []
        var node = element.parent
        var depth = 0
        while let n = node, depth < 12 {
            let r = n.role
            if r == "AXScrollArea" || r == "AXWebArea" { ancestors.append(n) }
            if r == "AXWindow" { ancestors.append(n); break }
            node = n.parent
            depth += 1
        }
        clipAncestors = ancestors
    }

    var isSingleLine: Bool { role == kAXTextFieldRole as String || role == kAXComboBoxRole as String }

    /// The on-screen part of the field, in Cocoa coordinates.
    func visibleFrame() -> CGRect? {
        guard var rect = element.axFrame, rect.width > 4, rect.height > 4 else { return nil }
        for a in clipAncestors {
            if let f = a.axFrame, f.width > 0, f.height > 0 {
                rect = rect.intersection(f)
            }
        }
        guard !rect.isNull, rect.width > 4, rect.height > 4 else { return nil }
        // AX reports frames even for windows on other Spaces or hidden apps.
        guard Self.isOnScreen(pid: pid, axRect: rect) else { return nil }
        let cocoa = ScreenGeometry.cocoa(rect)
        // Keep it on a real screen.
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(cocoa) }) else { return nil }
        let clipped = cocoa.intersection(screen.frame)
        return clipped.isNull ? nil : clipped
    }

    /// Whether one of the app's windows is really on the current screen where the field is.
    static func isOnScreen(pid: pid_t, axRect: CGRect) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return true }
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: b) else { return false }
            return bounds.intersects(axRect)
        }
    }

    /// Rects (Cocoa coordinates) covering `range`, one per line.
    func rects(for range: NSRange) -> [CGRect] {
        guard range.length > 0, let whole = element.axBounds(for: range), whole.width > 0 || whole.height > 0 else { return [] }

        // Single-line fast path: compare with the height of the first character.
        if let first = element.axBounds(for: NSRange(location: range.location, length: 1)),
           first.height > 0, whole.height > first.height * 1.6, range.length <= 400 {
            // Spans multiple lines: group characters by line.
            var lines: [CGRect] = []
            for i in 0..<range.length {
                guard let r = element.axBounds(for: NSRange(location: range.location + i, length: 1)), r.width > 0 else { continue }
                if let last = lines.last, abs(last.midY - r.midY) < first.height * 0.5 {
                    lines[lines.count - 1] = last.union(r)
                } else {
                    lines.append(r)
                }
            }
            return lines.map(ScreenGeometry.cocoa)
        }
        return [ScreenGeometry.cocoa(whole)]
    }
}
