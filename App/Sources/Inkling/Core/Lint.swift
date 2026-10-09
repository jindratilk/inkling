import AppKit
import SwiftUI

/// A small lesson attached to a suggestion — the "why".
struct Lesson: Codable, Hashable {
    var title: String
    var explanation: String
    var wrong: [String]
    var right: [String]
}

/// One issue found in the text. Offsets are UTF-16 (what AppKit & Accessibility use).
struct Lint: Codable, Hashable, Identifiable {
    var rule: String
    var kind: String
    var start: Int
    var end: Int
    var original: String
    var message: String
    var priority: Int
    var suggestions: [String]
    var description: String
    var lesson: Lesson?
    var severity: String

    /// Stable identity across edits (so underlines glide instead of flicker).
    var uid = UUID()

    enum CodingKeys: String, CodingKey {
        case rule, kind, start, end, original, message, priority, suggestions, description, lesson, severity
    }

    var id: UUID { uid }
    var range: NSRange { NSRange(location: start, length: max(0, end - start)) }
    var isHint: Bool { severity == "hint" }
    var isCoach: Bool { rule.hasPrefix("Coach.") }
    var isSpelling: Bool { rule == "SpellCheck" }
    var isAI: Bool { rule.hasPrefix("AI.") }
    var category: IssueCategory { IssueCategory(kind: kind, severity: severity, rule: rule) }

    /// Key used to remember dismissals for this session (never persisted).
    func dismissalKey(in text: String) -> String {
        let ns = text as NSString
        let s = min(max(0, start), ns.length)
        let e = min(max(s, end), ns.length)
        let before = NSRange(location: max(0, s - 12), length: s - max(0, s - 12))
        let after = NSRange(location: e, length: min(12, ns.length - e))
        return "\(rule)|\(original)|\(ns.substring(with: before))|\(ns.substring(with: after))"
    }

    func shifted(by delta: Int) -> Lint {
        var copy = self
        copy.start += delta
        copy.end += delta
        return copy
    }
}

enum IssueCategory: String, CaseIterable, Codable, Identifiable {
    case spelling, grammar, punctuation, wordChoice, clarity, tip

    var id: String { rawValue }

    init(kind: String, severity: String, rule: String) {
        if severity == "hint" && rule.hasPrefix("Coach.") {
            self = .tip
            return
        }
        switch kind {
        case "Spelling", "Typo", "BoundaryError", "Repetition": self = .spelling
        case "Capitalization", "Punctuation", "Formatting": self = .punctuation
        case "Usage", "WordChoice", "Eggcorn", "Malapropism", "Nonstandard", "Regionalism": self = .wordChoice
        case "Style", "Readability", "Enhancement", "Redundancy": self = .clarity
        default: self = .grammar
        }
    }

    var title: String {
        switch self {
        case .spelling: "Spelling"
        case .grammar: "Grammar"
        case .punctuation: "Punctuation"
        case .wordChoice: "Word choice"
        case .clarity: "Clarity"
        case .tip: "Tip"
        }
    }

    var symbol: String {
        switch self {
        case .spelling: "textformat.abc.dottedunderline"
        case .grammar: "text.badge.checkmark"
        case .punctuation: "ellipsis.curlybraces"
        case .wordChoice: "character.book.closed"
        case .clarity: "sparkles"
        case .tip: "lightbulb"
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    var nsColor: NSColor {
        switch self {
        case .spelling: NSColor(srgbRed: 1.00, green: 0.33, blue: 0.40, alpha: 1)    // coral
        case .grammar: NSColor(srgbRed: 1.00, green: 0.58, blue: 0.10, alpha: 1)     // amber
        case .punctuation: NSColor(srgbRed: 0.93, green: 0.29, blue: 0.62, alpha: 1) // magenta
        case .wordChoice: NSColor(srgbRed: 0.05, green: 0.62, blue: 0.62, alpha: 1)  // teal
        case .clarity: NSColor(srgbRed: 0.12, green: 0.37, blue: 0.75, alpha: 1)     // blueprint blue
        case .tip: NSColor(srgbRed: 0.04, green: 0.62, blue: 0.88, alpha: 1)         // sky (dotted)
        }
    }

    /// Lower sorts first: what we surface on the badge.
    var importance: Int {
        switch self {
        case .spelling: 0
        case .grammar: 1
        case .wordChoice: 2
        case .punctuation: 3
        case .clarity: 4
        case .tip: 5
        }
    }
}

struct LessonEntry: Codable, Hashable, Identifiable {
    var rule: String
    var kind: String
    var lesson: Lesson
    var id: String { rule }
}

enum DocLanguage: Equatable {
    case english
    case notEnglish
    case undetermined
}
