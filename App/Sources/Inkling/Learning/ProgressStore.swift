import Combine
import Foundation

/// Learning progress. Stores *counts per rule per day* only — never any text,
/// words or sentences you wrote.
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()

    struct Day: Codable {
        var seen: [String: Int] = [:]
        var fixed: [String: Int] = [:]
        var dismissed: [String: Int] = [:]
    }

    private struct File: Codable {
        var days: [String: Day]
        var ruleCategories: [String: String]
    }

    @Published private(set) var days: [String: Day] = [:]
    @Published private(set) var ruleCategories: [String: String] = [:]

    private var saveWork: DispatchWorkItem?
    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inkling", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("progress.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) {
            days = file.days
            ruleCategories = file.ruleCategories
        }
    }

    static func key(for date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: recording

    func recordSeen(_ lint: Lint) { bump(\.seen, lint) }
    func recordFixed(_ lint: Lint) { bump(\.fixed, lint) }
    func recordDismissed(_ lint: Lint) { bump(\.dismissed, lint) }

    private func bump(_ path: WritableKeyPath<Day, [String: Int]>, _ lint: Lint) {
        let k = Self.key()
        var day = days[k] ?? Day()
        day[keyPath: path][lint.rule, default: 0] += 1
        days[k] = day
        ruleCategories[lint.rule] = lint.category.rawValue
        scheduleSave()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func save() {
        let file = File(days: days, ruleCategories: ruleCategories)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    func reset() {
        days = [:]
        ruleCategories = [:]
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: insights

    var today: Day { days[Self.key()] ?? Day() }
    var todaySeen: Int { today.seen.values.reduce(0, +) }
    var todayFixed: Int { today.fixed.values.reduce(0, +) }

    /// Consecutive days (ending today or yesterday) with at least one fix.
    var streak: Int {
        var count = 0
        var date = Date()
        if (days[Self.key(for: date)]?.fixed.values.reduce(0, +) ?? 0) == 0 {
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        while (days[Self.key(for: date)]?.fixed.values.reduce(0, +) ?? 0) > 0 {
            count += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return count
    }

    private func recentDays(_ n: Int) -> [Day] {
        (0..<n).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: Date()).flatMap { days[Self.key(for: $0)] }
        }
    }

    /// Most frequent rules over the last `n` days.
    func topRules(days n: Int = 30, limit: Int = 6) -> [(rule: String, count: Int)] {
        var totals: [String: Int] = [:]
        for d in recentDays(n) {
            for (rule, c) in d.seen { totals[rule, default: 0] += c }
        }
        return totals.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    func categoryTotals(days n: Int = 30) -> [IssueCategory: Int] {
        var totals: [IssueCategory: Int] = [:]
        for d in recentDays(n) {
            for (rule, c) in d.seen {
                let cat = IssueCategory(rawValue: ruleCategories[rule] ?? "") ?? .grammar
                totals[cat, default: 0] += c
            }
        }
        return totals
    }

    /// (date, seen, fixed) for the last `n` days, oldest first.
    func series(days n: Int = 14) -> [(date: Date, seen: Int, fixed: Int)] {
        (0..<n).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let d = days[Self.key(for: date)]
            return (date, d?.seen.values.reduce(0, +) ?? 0, d?.fixed.values.reduce(0, +) ?? 0)
        }
    }

    var totalFixed: Int { days.values.reduce(0) { $0 + $1.fixed.values.reduce(0, +) } }
}
