import CInklingEngine
import Foundation

struct EngineConfig: Codable, Equatable {
    var dialect: String
    var userWords: [String]
    var disabledRules: [String]
    var coach: Bool
    var style: Bool
}

/// Swift face of the Rust engine (Harper + Inkling coach).
/// All calls into Rust happen on `queue`, one at a time.
final class GrammarEngine: @unchecked Sendable {
    let queue = DispatchQueue(label: "app.inkling.engine", qos: .userInitiated)
    private var handle: OpaquePointer?
    private(set) var config: EngineConfig
    /// Bumped whenever the engine is rebuilt so caches know to flush.
    private(set) var revision = 0

    private struct CheckDTO: Decodable {
        let lints: [Lint]
        let micros: Int
    }

    init(config: EngineConfig) {
        self.config = config
        queue.async { self.build() }
    }

    deinit {
        if let handle { inkling_engine_free(handle) }
    }

    private func build() {
        if let handle { inkling_engine_free(handle) }
        let json = (try? JSONEncoder().encode(config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        handle = json.withCString { inkling_engine_new($0) }
        revision += 1
    }

    func reconfigure(_ newConfig: EngineConfig) {
        queue.async {
            guard newConfig != self.config else { return }
            self.config = newConfig
            self.build()
        }
    }

    /// Lint one chunk of text. Must be called on `queue`.
    func lint(_ text: String) -> (lints: [Lint], micros: Int) {
        dispatchPrecondition(condition: .onQueue(queue))
        if handle == nil { build() }
        guard let handle, let raw = text.withCString({ inkling_engine_check(handle, $0) }) else { return ([], 0) }
        defer { inkling_string_free(raw) }
        let data = Data(bytes: raw, count: strlen(raw))
        guard let dto = try? JSONDecoder().decode(CheckDTO.self, from: data) else { return ([], 0) }
        return (dto.lints, dto.micros)
    }

    func ruleDescriptions(_ completion: @escaping ([String: String]) -> Void) {
        queue.async {
            if self.handle == nil { self.build() }
            var result: [String: String] = [:]
            if let handle = self.handle, let raw = inkling_engine_rule_descriptions(handle) {
                let data = Data(bytes: raw, count: strlen(raw))
                inkling_string_free(raw)
                result = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Every coach lesson (static content compiled into the engine).
    static let coachLessons: [LessonEntry] = {
        guard let raw = inkling_coach_lessons() else { return [] }
        defer { inkling_string_free(raw) }
        let data = Data(bytes: raw, count: strlen(raw))
        return (try? JSONDecoder().decode([LessonEntry].self, from: data)) ?? []
    }()
}
