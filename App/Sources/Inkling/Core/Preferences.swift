import Combine
import Foundation

enum EnglishDialect: String, CaseIterable, Identifiable, Codable {
    case american, british, canadian, australian

    var id: String { rawValue }
    var label: String {
        switch self {
        case .american: "American"
        case .british: "British"
        case .canadian: "Canadian"
        case .australian: "Australian"
        }
    }
    var flag: String {
        switch self {
        case .american: "🇺🇸"
        case .british: "🇬🇧"
        case .canadian: "🇨🇦"
        case .australian: "🇦🇺"
        }
    }
}

/// User settings. Only preferences live here — never any of the user's text.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var isEnabled: Bool
    @Published var pausedUntil: Date?
    @Published var dialect: EnglishDialect
    @Published var checkSpelling: Bool
    @Published var checkGrammar: Bool
    @Published var checkPunctuation: Bool
    @Published var checkClarity: Bool
    @Published var coach: Bool
    @Published var aiSuggestions: Bool
    @Published var disabledRules: [String]
    @Published var userWords: [String]
    @Published var excludedApps: [String]
    @Published var showBadge: Bool
    @Published var onboarded: Bool

    static let defaultDisabledRules = [
        "AvoidCurses", "ExpandTimeShorthands", "ExpandMemoryShorthands", "OxfordComma",
        "NoOxfordComma", "SpelledNumbers", "BoringWords", "AvoidContractions", "FillerWords",
        "UseEllipsisCharacter", "Dashes", "NoFrenchSpaces",
    ]

    static let defaultExcludedApps = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.apple.dt.Xcode", "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "dev.zed.Zed",
        "com.sublimetext.4", "com.1password.1password", "com.apple.keychainaccess", "com.apple.Passwords",
        "com.jetbrains.", "com.apple.ScriptEditor2", "com.bitwarden.desktop",
    ]

    private let defaults = UserDefaults.standard
    private var bag = Set<AnyCancellable>()

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "isEnabled": true, "checkSpelling": true, "checkGrammar": true, "checkPunctuation": true,
            "checkClarity": true, "coach": true, "aiSuggestions": true, "showBadge": true,
            "dialect": EnglishDialect.american.rawValue,
            "onboarded": false,
        ])
        isEnabled = d.bool(forKey: "isEnabled")
        pausedUntil = d.object(forKey: "pausedUntil") as? Date
        dialect = EnglishDialect(rawValue: d.string(forKey: "dialect") ?? "") ?? .american
        checkSpelling = d.bool(forKey: "checkSpelling")
        checkGrammar = d.bool(forKey: "checkGrammar")
        checkPunctuation = d.bool(forKey: "checkPunctuation")
        checkClarity = d.bool(forKey: "checkClarity")
        coach = d.bool(forKey: "coach")
        aiSuggestions = d.bool(forKey: "aiSuggestions")
        disabledRules = d.stringArray(forKey: "disabledRules") ?? Self.defaultDisabledRules
        userWords = d.stringArray(forKey: "userWords") ?? []
        excludedApps = d.stringArray(forKey: "excludedApps") ?? Self.defaultExcludedApps
        showBadge = d.bool(forKey: "showBadge")
        onboarded = d.bool(forKey: "onboarded")

        objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] in self?.save() }
            .store(in: &bag)
    }

    private func save() {
        let d = defaults
        d.set(isEnabled, forKey: "isEnabled")
        d.set(pausedUntil, forKey: "pausedUntil")
        d.set(dialect.rawValue, forKey: "dialect")
        d.set(checkSpelling, forKey: "checkSpelling")
        d.set(checkGrammar, forKey: "checkGrammar")
        d.set(checkPunctuation, forKey: "checkPunctuation")
        d.set(checkClarity, forKey: "checkClarity")
        d.set(coach, forKey: "coach")
        d.set(aiSuggestions, forKey: "aiSuggestions")
        d.set(disabledRules, forKey: "disabledRules")
        d.set(userWords, forKey: "userWords")
        d.set(excludedApps, forKey: "excludedApps")
        d.set(showBadge, forKey: "showBadge")
        d.set(onboarded, forKey: "onboarded")
    }

    // MARK: derived

    var isPaused: Bool {
        if let until = pausedUntil { return until > Date() }
        return false
    }

    var isActive: Bool { isEnabled && !isPaused }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return excludedApps.contains { $0.hasSuffix(".") ? id.hasPrefix($0) : id == $0 }
    }

    func allows(_ category: IssueCategory) -> Bool {
        switch category {
        case .spelling: checkSpelling
        case .grammar, .wordChoice: checkGrammar
        case .punctuation: checkPunctuation
        case .clarity: checkClarity
        case .tip: coach
        }
    }

    var engineConfig: EngineConfig {
        EngineConfig(
            dialect: dialect.rawValue,
            userWords: userWords,
            disabledRules: disabledRules,
            coach: coach,
            style: checkClarity
        )
    }

    func addWord(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !userWords.contains(w) else { return }
        userWords.append(w)
        userWords.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func disableRule(_ rule: String) {
        guard !disabledRules.contains(rule) else { return }
        disabledRules.append(rule)
    }

    func pause(for interval: TimeInterval?) {
        pausedUntil = interval.map { Date().addingTimeInterval($0) }
    }
}
