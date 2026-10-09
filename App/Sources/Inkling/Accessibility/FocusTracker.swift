import AppKit
import ApplicationServices

@MainActor
protocol FocusTrackerDelegate: AnyObject {
    func trackerDidChangeField(_ field: TrackedField?)
    func trackerTextDidChange(_ field: TrackedField, from oldText: String)
    func trackerSelectionDidChange(_ field: TrackedField)
    func trackerGeometryDidChange()
}

/// Follows keyboard focus across apps via the Accessibility API and reports the
/// editable text field the user is typing in. Reads text only — in memory.
@MainActor
final class FocusTracker {
    weak var delegate: FocusTrackerDelegate?
    private(set) var field: TrackedField?
    private(set) var isRunning = false

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var observedApp: NSRunningApplication?
    private var pollTimer: Timer?
    private var workspaceTokens: [NSObjectProtocol] = []
    private let systemWide = AXUIElementCreateSystemWide()

    private static let watchedNotifications: [String] = [
        kAXFocusedUIElementChangedNotification,
        kAXFocusedWindowChangedNotification,
        kAXValueChangedNotification,
        kAXSelectedTextChangedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXMovedNotification,
        kAXResizedNotification,
    ]

    private static let blockedHints = ["password", "heslo", "passcode", "search", "hledat", "address and search", "url", "smart search"]

    func start() {
        guard !isRunning else { return }
        isRunning = true
        AXUIElementSetMessagingTimeout(systemWide, 0.3)

        let nc = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.attach(to: app) }
        })
        workspaceTokens.append(nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.delegate?.trackerGeometryDidChange() }
        })

        attach(to: NSWorkspace.shared.frontmostApplication)

        // Safety net for apps that don't post AX notifications reliably.
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens.removeAll()
        detachObserver()
        setField(nil)
    }

    // MARK: attaching

    private func attach(to app: NSRunningApplication?) {
        guard isRunning else { return }
        guard let app, app.processIdentifier != getpid() else {
            // Our own panels/menus: keep the previous field so the card can work.
            return
        }
        if app.processIdentifier == observedPID, observer != nil {
            refreshFocus()
            return
        }
        detachObserver()
        observedPID = app.processIdentifier
        observedApp = app

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        // Ask Electron / Chromium apps to expose their accessibility tree.
        appElement.set("AXManualAccessibility", kCFBooleanTrue)

        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            MainActor.assumeIsolated { tracker.handle(name, element: element) }
        }
        guard AXObserverCreate(app.processIdentifier, callback, &obs) == .success, let obs else {
            refreshFocus()
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.watchedNotifications {
            AXObserverAddNotification(obs, appElement, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        refreshFocus()
    }

    private func detachObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = 0
        observedApp = nil
    }

    // MARK: events

    private func handle(_ name: String, element: AXUIElement) {
        switch name {
        case kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification:
            refreshFocus()
        case kAXValueChangedNotification:
            if let field, field.element.isSame(as: element) { readText() } else { refreshFocus() }
        case kAXSelectedTextChangedNotification:
            if let field, field.element.isSame(as: element) {
                readText()
                let sel = field.element.selectedRange
                if sel != field.selection {
                    field.selection = sel
                    delegate?.trackerSelectionDidChange(field)
                }
            }
        default:
            delegate?.trackerGeometryDidChange()
        }
    }

    private func poll() {
        guard isRunning else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.processIdentifier != getpid(), front.processIdentifier != observedPID {
            attach(to: front)
            return
        }
        if front?.processIdentifier == getpid() { return }
        refreshFocus()
    }

    func refreshFocus() {
        guard isRunning, let app = observedApp else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        let focused = appElement.element(kAXFocusedUIElementAttribute) ?? systemWide.element(kAXFocusedUIElementAttribute)

        guard let el = focused, el.pid == app.processIdentifier, Self.isEditableText(el), let text = el.value else {
            setField(nil)
            return
        }
        if let field, field.element.isSame(as: el) {
            readText(text)
            return
        }
        setField(TrackedField(element: el, app: app, text: text))
    }

    private func readText(_ known: String? = nil) {
        guard let field else { return }
        guard let text = known ?? field.element.value else { return }
        if text != field.text {
            let old = field.text
            field.text = text
            field.selection = field.element.selectedRange
            delegate?.trackerTextDidChange(field, from: old)
        }
    }

    private func setField(_ newField: TrackedField?) {
        if newField == nil && field == nil { return }
        field = newField
        delegate?.trackerDidChangeField(newField)
    }

    // MARK: classification

    static func isEditableText(_ el: AXUIElement) -> Bool {
        let role = el.role ?? ""
        let subrole = el.subrole ?? ""
        if subrole == (kAXSecureTextFieldSubrole as String) || role == "AXSecureTextField" { return false }
        if subrole == (kAXSearchFieldSubrole as String) { return false }

        let hints = [el.string(kAXDescriptionAttribute), el.string(kAXIdentifierAttribute), el.string(kAXPlaceholderValueAttribute), el.string(kAXTitleAttribute)]
            .compactMap { $0?.lowercased() }
        if hints.contains(where: { h in blockedHints.contains { h.contains($0) } }) { return false }

        switch role {
        case kAXTextAreaRole as String, kAXTextFieldRole as String, kAXComboBoxRole as String:
            return el.isSettable(kAXValueAttribute) || el.isSettable(kAXSelectedTextAttribute) || role == kAXTextAreaRole as String
        default:
            return el.isSettable(kAXValueAttribute) && el.value != nil && role != "AXStaticText"
        }
    }
}
