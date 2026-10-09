import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences.shared
    private let state = AppState.shared

    private var engine: GrammarEngine!
    private var pipeline: CheckPipeline!
    private var tracker: FocusTracker!
    private var overlay: OverlayController!
    private var statusItem: StatusItemController!
    private let windows = WindowsCoordinator()
    private var hotKey: HotKey?
    private var trustTimer: Timer?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = GrammarEngine(config: prefs.engineConfig)
        pipeline = CheckPipeline(engine: engine)
        overlay = OverlayController(pipeline: pipeline)
        tracker = FocusTracker()
        tracker.delegate = overlay

        statusItem = StatusItemController(actions: MenuActions(
            openSettings: { [weak self] pane in self?.windows.showSettings(pane) },
            openOnboarding: { [weak self] in self?.windows.showOnboarding() },
            toggleExclusion: { [weak self] id in self?.toggleExclusion(id) },
            quit: { NSApp.terminate(nil) }
        ))

        windows.onOnboardingFinished = { [weak self] in
            self?.startIfPossible()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.statusItem.show() }
        }

        // Rebuild the engine when settings that affect checking change.
        prefs.objectWillChange
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.engine.reconfigure(self.prefs.engineConfig)
                self.tracker.refreshFocus()
            }
            .store(in: &bag)

        // ⌃⌥I — open the review list for the field you're in.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_I), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.overlay.toggleReview()
        }

        // Accessibility permission can be granted at any time; notice it.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTrust() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer

        if !prefs.onboarded || !AXIsProcessTrusted() {
            windows.showOnboarding()
        }
        startIfPossible()
    }

    private func checkTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted != state.trusted {
            state.trusted = trusted
            if trusted { startIfPossible() } else { tracker.stop() }
        }
    }

    private func startIfPossible() {
        state.trusted = AXIsProcessTrusted()
        guard state.trusted, !tracker.isRunning else { return }
        tracker.start()
    }

    private func toggleExclusion(_ id: String) {
        if prefs.isExcluded(id) {
            prefs.excludedApps.removeAll { $0 == id || (id.hasPrefix($0) && $0.hasSuffix(".")) }
        } else {
            prefs.excludedApps.append(id)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showSettings()
        return true
    }
}
