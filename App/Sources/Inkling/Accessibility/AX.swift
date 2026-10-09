import AppKit
import ApplicationServices

/// Tiny typed wrappers around the Accessibility C API.
extension AXUIElement {
    func raw(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ attribute: String) -> String? { raw(attribute) as? String }

    func element(_ attribute: String) -> AXUIElement? {
        guard let v = raw(attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    func axValue(_ attribute: String) -> AXValue? {
        guard let v = raw(attribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        return (v as! AXValue)
    }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var value: String? { string(kAXValueAttribute) }
    var parent: AXUIElement? { element(kAXParentAttribute) }
    var window: AXUIElement? { element(kAXWindowAttribute) }

    var pid: pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(self, &p)
        return p
    }

    var selectedRange: NSRange? {
        guard let v = axValue(kAXSelectedTextRangeAttribute) else { return nil }
        var r = CFRange()
        guard AXValueGetValue(v, .cfRange, &r) else { return nil }
        return NSRange(location: r.location, length: r.length)
    }

    var visibleCharacterRange: NSRange? {
        guard let v = axValue(kAXVisibleCharacterRangeAttribute) else { return nil }
        var r = CFRange()
        guard AXValueGetValue(v, .cfRange, &r) else { return nil }
        return NSRange(location: r.location, length: r.length)
    }

    /// Frame in AX (top-left origin) screen coordinates.
    var axFrame: CGRect? {
        guard let p = axValue(kAXPositionAttribute), let s = axValue(kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success && settable.boolValue
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    @discardableResult
    func setSelectedRange(_ range: NSRange) -> Bool {
        var r = CFRange(location: range.location, length: range.length)
        guard let v = AXValueCreate(.cfRange, &r) else { return false }
        return set(kAXSelectedTextRangeAttribute, v)
    }

    /// Bounds of a character range, in AX (top-left origin) screen coordinates.
    func axBounds(for range: NSRange) -> CGRect? {
        var r = CFRange(location: range.location, length: range.length)
        guard let param = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(self, kAXBoundsForRangeParameterizedAttribute as CFString, param, &out) == .success,
              let out, CFGetTypeID(out) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(out as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    func isSame(as other: AXUIElement?) -> Bool {
        guard let other else { return false }
        return CFEqual(self, other)
    }
}

enum ScreenGeometry {
    /// Height of the primary display — the pivot between AX and Cocoa coordinates.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }

    /// AX (top-left origin) → Cocoa (bottom-left origin).
    static func cocoa(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
