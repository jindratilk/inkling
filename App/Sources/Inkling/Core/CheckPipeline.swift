import Foundation
import NaturalLanguage

struct CheckOutcome {
    let text: String
    let lints: [Lint]
    let language: DocLanguage
    let micros: Int
    let token: Int
}

/// Splits text into paragraphs, gates each sentence by language, lints English
/// paragraphs with the engine and caches results per paragraph so typing in a
/// long document only re-checks the paragraph you're in.
final class CheckPipeline: @unchecked Sendable {
    let engine: GrammarEngine

    private struct ParagraphResult {
        var lints: [Lint]
        var englishUnits: Int
        var otherUnits: Int
    }

    // Only touched on engine.queue
    private var cache: [String: ParagraphResult] = [:]
    private var cacheRevision = -1

    // Coalescing: only the newest request runs.
    private let lock = NSLock()
    private var pending: (text: String, focus: NSRange?, token: Int, completion: (CheckOutcome) -> Void)?
    private var running = false

    init(engine: GrammarEngine) {
        self.engine = engine
    }

    func submit(text: String, focus: NSRange?, token: Int, completion: @escaping (CheckOutcome) -> Void) {
        lock.lock()
        pending = (text, focus, token, completion)
        let shouldStart = !running
        running = true
        lock.unlock()
        if shouldStart { engine.queue.async { self.drain() } }
    }

    func invalidateCache() {
        engine.queue.async { self.cache.removeAll() }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let job = pending else {
                running = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()

            let outcome = run(text: job.text, focus: job.focus, token: job.token)
            DispatchQueue.main.async { job.completion(outcome) }
        }
    }

    private func run(text: String, focus: NSRange?, token: Int) -> CheckOutcome {
        let started = DispatchTime.now()
        if cacheRevision != engine.revision {
            cache.removeAll()
            cacheRevision = engine.revision
        }
        if cache.count > 4000 { cache.removeAll() }

        let ns = text as NSString
        var lints: [Lint] = []
        var english = 0
        var other = 0

        // In very long documents, only look around what's on screen.
        let window: NSRange? = {
            guard ns.length > 40_000 else { return nil }
            let f = focus ?? NSRange(location: 0, length: 0)
            let start = max(0, f.location - 4000)
            let end = min(ns.length, NSMaxRange(f) + 4000)
            return NSRange(location: start, length: end - start)
        }()

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs]) { sub, range, _, _ in
            guard let paragraph = sub else { return }
            if let window, NSIntersectionRange(window, range).length == 0 { return }
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix(">") { return }

            let result: ParagraphResult
            if let hit = self.cache[paragraph] {
                result = hit
            } else {
                result = self.analyze(paragraph)
                self.cache[paragraph] = result
            }
            english += result.englishUnits
            other += result.otherUnits
            if !result.lints.isEmpty {
                lints.append(contentsOf: result.lints.map { $0.shifted(by: range.location) })
            }
        }

        let language: DocLanguage
        if english == 0 && other == 0 {
            language = .undetermined
        } else if other > english {
            language = .notEnglish
        } else {
            language = .english
        }

        let micros = Int((DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1000)
        return CheckOutcome(text: text, lints: language == .english ? lints : [], language: language, micros: micros, token: token)
    }

    private func analyze(_ paragraph: String) -> ParagraphResult {
        let paragraphVerdict = LanguageGate.classify(paragraph)

        // Sentence-level gating lets a Czech sentence live inside an English email untouched.
        var sentences: [(range: NSRange, verdict: LanguageGate.Verdict)] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraph
        tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { r, _ in
            let sentence = String(paragraph[r])
            var verdict = LanguageGate.classify(sentence)
            if verdict == .unknown { verdict = paragraphVerdict }
            sentences.append((NSRange(r, in: paragraph), verdict))
            return true
        }
        if sentences.isEmpty {
            sentences = [(NSRange(location: 0, length: (paragraph as NSString).length), paragraphVerdict)]
        }

        var english = 0
        var other = 0
        for s in sentences {
            switch s.verdict {
            case .english: english += s.range.length
            case .other: other += s.range.length
            case .unknown: break
            }
        }

        guard english > 0 else { return ParagraphResult(lints: [], englishUnits: 0, otherUnits: other) }

        let englishRanges = sentences.filter { $0.verdict == .english }.map(\.range)
        let lints = engine.lint(paragraph).lints.filter { lint in
            englishRanges.contains { NSLocationInRange(lint.start, $0) || (lint.start == NSMaxRange($0) && lint.end == lint.start) }
        }
        return ParagraphResult(lints: lints, englishUnits: english, otherUnits: other)
    }
}
