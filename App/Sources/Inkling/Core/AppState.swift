import AppKit
import Combine

/// Live, in-memory status shown in the menu bar. Nothing here is persisted.
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var trusted = AXIsProcessTrusted()
    @Published var appName: String?
    @Published var bundleID: String?
    @Published var appIcon: NSImage?
    @Published var hasField = false
    @Published var language: DocLanguage = .undetermined
    @Published var issueCount = 0
    @Published var categoryCounts: [IssueCategory: Int] = [:]
    @Published var lastCheckMicros = 0

    enum Status: Equatable {
        case needsPermission
        case off
        case paused
        case excluded
        case idle
        case quietCzech
        case checking
    }

    func status(_ prefs: Preferences) -> Status {
        if !trusted { return .needsPermission }
        if !prefs.isEnabled { return .off }
        if prefs.isPaused { return .paused }
        if prefs.isExcluded(bundleID) { return .excluded }
        guard hasField else { return .idle }
        if language == .notEnglish { return .quietCzech }
        return .checking
    }
}
