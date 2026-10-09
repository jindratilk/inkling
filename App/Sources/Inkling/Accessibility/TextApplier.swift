import AppKit
import ApplicationServices

/// Writes a correction back into the other app's text field.
/// Tries the clean Accessibility route first (keeps the app's undo), then a
/// pasteboard fallback that restores your clipboard afterwards.
@MainActor
enum TextApplier {
    enum Result { case applied, stale, failed }

    static func apply(_ replacement: String, for lint: Lint, in field: TrackedField) -> Result {
        let el = field.element
        guard let current = el.value else { return .failed }
        let ns = current as NSString
        guard NSMaxRange(lint.range) <= ns.length, ns.substring(with: lint.range) == lint.original else { return .stale }

        let caret = el.selectedRange
        let delta = (replacement as NSString).length - lint.range.length
        // Success means the *whole* field now reads exactly as expected — this also
        // catches deletions, where there is no replacement text to look for.
        let expected = ns.replacingCharacters(in: lint.range, with: replacement)
        func norm(_ s: String?) -> String? { s?.replacingOccurrences(of: "\u{00A0}", with: " ") }
        let landed = { norm(el.value) == norm(expected) }

        // 1) Select the flagged text and replace the selection (keeps the app's undo).
        el.setSelectedRange(lint.range)
        if el.selectedRange == lint.range {
            if el.set(kAXSelectedTextAttribute, replacement as CFString), wait(for: landed, timeout: 0.15) {
                restoreCaret(el, caret: caret, lint: lint, delta: delta)
                return .applied
            }
            guard stillOriginal(el, lint) else {
                // The app changed the text some other way; never risk a double edit.
                return landed() ? .applied : .stale
            }
            // 2) Keyboard fallback for editors that ignore AX writes (Electron, web editors).
            if el.selectedRange != lint.range { el.setSelectedRange(lint.range) }
            if el.selectedRange == lint.range {
                if replacement.isEmpty { pressDelete() } else { paste(replacement) }
                if wait(for: landed, timeout: 0.6) { return .applied }
                return stillOriginal(el, lint) ? .failed : .applied
            }
        }

        // 3) Last resort for native fields: rewrite the whole value (may lose undo).
        if el.isSettable(kAXValueAttribute), el.set(kAXValueAttribute, expected as CFString), wait(for: landed, timeout: 0.15) {
            restoreCaret(el, caret: caret, lint: lint, delta: delta)
            return .applied
        }
        return .failed
    }

    /// Spin the run loop briefly until `condition` holds (apps apply edits asynchronously).
    private static func wait(for condition: () -> Bool, timeout: TimeInterval) -> Bool {
        if condition() { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            if condition() { return true }
        }
        return false
    }

    private static func pressDelete() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func stillOriginal(_ el: AXUIElement, _ lint: Lint) -> Bool {
        guard let now = el.value as NSString?, NSMaxRange(lint.range) <= now.length else { return false }
        return now.substring(with: lint.range) == lint.original
    }

    private static func restoreCaret(_ el: AXUIElement, caret: NSRange?, lint: Lint, delta: Int) {
        guard let caret else { return }
        var target = caret
        if caret.location >= lint.end {
            target.location += delta
        } else if caret.location > lint.start {
            target = NSRange(location: lint.start + (lint.range.length + delta), length: 0)
        }
        el.setSelectedRange(NSRange(location: max(0, target.location), length: 0))
    }

    private static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let d = item.data(forType: t) { dict[t] = d } }
            return dict
        }
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // Ask clipboard managers to ignore this temporary entry.
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.writeObjects([item])

        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            pb.clearContents()
            let items = saved.map { dict -> NSPasteboardItem in
                let i = NSPasteboardItem()
                for (t, d) in dict { i.setData(d, forType: t) }
                return i
            }
            if !items.isEmpty { pb.writeObjects(items) }
        }
    }
}
