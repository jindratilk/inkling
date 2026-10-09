import AppKit
import SwiftUI

/// Regular windows (onboarding, settings). Inkling is a menu bar app, so we
/// briefly become a regular app while one of these is open.
@MainActor
final class WindowsCoordinator: NSObject, NSWindowDelegate {
    private var onboarding: NSWindow?
    private var settings: NSWindow?
    let router = SettingsRouter()
    var onOnboardingFinished: (() -> Void)?

    func showOnboarding() {
        if onboarding == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: OnboardingView(finish: { [weak self] in
                self?.onboarding?.close()
                self?.onOnboardingFinished?()
            }))
            window.delegate = self
            window.center()
            onboarding = window
        }
        present(onboarding)
    }

    func showSettings(_ pane: SettingsPane = .general) {
        router.pane = pane
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 580), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Inkling"
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(router: router))
            window.setContentSize(NSSize(width: 820, height: 580))
            window.delegate = self
            window.center()
            settings = window
        }
        present(settings)
    }

    private func present(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            let anyOpen = [self.onboarding, self.settings].contains { $0?.isVisible == true }
            if !anyOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

enum Permissions {
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            openAccessibilitySettings()
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
