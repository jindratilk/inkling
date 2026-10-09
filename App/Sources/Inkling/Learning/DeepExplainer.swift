import Foundation
import FoundationModels

/// Optional "Explain more" powered by Apple's on-device model (Apple Intelligence).
/// The sentence is processed by the local model only and never stored.
@MainActor
final class DeepExplainer: ObservableObject {
    @Published private(set) var text = ""
    @Published private(set) var isStreaming = false
    @Published private(set) var failed = false

    private var task: Task<Void, Never>?

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func explain(lint: Lint, sentence: String) {
        task?.cancel()
        text = ""
        failed = false
        isStreaming = true

        let instructions = """
        You are Inkling, a warm and precise English tutor for someone who wants to improve their English. \
        Explain grammar in plain words, in at most 4 short sentences, then give one extra example sentence. \
        Never use headings, bullet lists or markdown. Be encouraging but never cheesy.
        """
        let fix = lint.suggestions.first.map { "The suggested correction is “\($0)”." } ?? ""
        let lang = "Write your explanation in simple English."
        let prompt = """
        Sentence: “\(sentence)”
        The part “\(lint.original)” was flagged: \(lint.message) \(fix)
        Explain why, and how to remember it. \(lang)
        """

        task = Task { [weak self] in
            do {
                let session = LanguageModelSession(instructions: instructions)
                let stream = session.streamResponse(to: prompt)
                for try await snapshot in stream {
                    if Task.isCancelled { return }
                    self?.text = snapshot.content
                }
            } catch {
                self?.failed = true
            }
            self?.isStreaming = false
        }
    }

    func cancel() {
        task?.cancel()
        isStreaming = false
    }
}
