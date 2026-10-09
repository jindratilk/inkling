import Foundation
import NaturalLanguage

/// Decides whether a piece of text is English. Czech (and other languages)
/// are left completely alone — Inkling stays invisible for them.
enum LanguageGate {
    enum Verdict: Equatable {
        case english
        case other
        case unknown
    }

    /// Letters that only show up in Czech (and close relatives), never in English.
    private static let czechLetters = Set("ěščřžůťďňĚŠČŘŽŮŤĎŇ")

    /// Common Czech words typed without diacritics that are *not* English words.
    private static let czechWords: Set<String> = [
        "ahoj", "cau", "jak", "se", "je", "jsem", "jsi", "jsme", "jste", "jsou", "byl", "byla", "bylo",
        "byli", "neni", "mam", "mas", "mame", "maji", "proc", "kde", "kdy", "taky", "uz",
        "jeste", "tady", "ktery", "ktera", "ktere", "nebo", "jenom", "asi", "moc", "velmi",
        "dobre", "diky", "dekuju", "dekuji", "prosim", "ano", "nevim", "muzu", "muzes", "muze", "chci",
        "chces", "bude", "budu", "budes", "jejich", "jeho", "jeji",
        "tohle", "tento", "tato", "toto", "dneska", "dnes", "zitra", "vcera", "potom", "protoze", "kdyz",
        "jestli", "takze", "fakt", "jasne", "hned", "aby", 
        "neco", "nekdo", "vsechno", "vubec", "porad", "treba", "mozna", "urcite", "spis", "jsme", 
        "mela", "melo", "uvidime", "zatim", "dobry", "vecer", "rano", "pozdrav", "pozdravem", "hezky",
        "zni", "hotove", "posilam", "priloze", "praci", "prijdes", "domu", "stihnu", 
    ]

    static func classify(_ text: String) -> Verdict {
        let words = text
            .split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" })
            .map { String($0) }
        guard !words.isEmpty else { return .unknown }

        let diacriticWords = words.filter { $0.contains(where: { czechLetters.contains($0) }) }.count
        if diacriticWords > 0 && (words.count < 6 || Double(diacriticWords) / Double(words.count) >= 0.12) {
            return .other
        }

        let czechHits = words.filter { czechWords.contains($0.lowercased()) }.count

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .czech, .slovak, .polish]
        recognizer.processString(text)
        let h = recognizer.languageHypotheses(withMaximum: 4)
        let english = h[.english] ?? 0
        let slavic = (h[.czech] ?? 0) + (h[.slovak] ?? 0) + (h[.polish] ?? 0)

        // Czech needs positive evidence. Anything else — including messy,
        // misspelled English — is treated as English, so checking never
        // silently switches off.
        if czechHits >= 2 { return .other }
        if czechHits >= 1 && english < 0.6 { return .other }
        if words.count >= 4 && slavic >= 0.92 && english < 0.05 { return .other }
        return .english
    }
}
