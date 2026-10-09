import Charts
import ServiceManagement
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, checks, lessons, progress, dictionary, apps, privacy

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .checks: "Checks"
        case .lessons: "Lessons"
        case .progress: "Progress"
        case .dictionary: "Dictionary"
        case .apps: "Apps"
        case .privacy: "Privacy"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .checks: "checklist"
        case .lessons: "graduationcap"
        case .progress: "chart.bar.xaxis"
        case .dictionary: "character.book.closed"
        case .apps: "square.grid.2x2"
        case .privacy: "lock.shield"
        }
    }
    var tint: Color {
        switch self {
        case .general: .gray
        case .checks: IssueCategory.grammar.color
        case .lessons: Ink.blueprint
        case .progress: Ink.mint
        case .dictionary: IssueCategory.wordChoice.color
        case .apps: IssueCategory.clarity.color
        case .privacy: Ink.coral
        }
    }
}

final class SettingsRouter: ObservableObject {
    @Published var pane: SettingsPane = .general
    @Published var focusRule: String?
}

struct SettingsView: View {
    @ObservedObject var router: SettingsRouter

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(get: { router.pane }, set: { if let p = $0 { router.pane = p } })) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.symbol)
                        .foregroundStyle(.white)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pane.tint.gradient))
                }
                .tag(pane)
                .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 230)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    InklingMark(size: 22, glow: false)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Inkling").font(.system(size: 12, weight: .bold, design: .rounded))
                        Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(12)
            }
        } detail: {
            Group {
                switch router.pane {
                case .general: GeneralPane()
                case .checks: ChecksPane()
                case .lessons: LessonsPane(router: router)
                case .progress: ProgressPane(router: router)
                case .dictionary: DictionaryPane()
                case .apps: AppsPane()
                case .privacy: PrivacyPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity)
            .id(router.pane)
        }
        .frame(minWidth: 760, minHeight: 540)
    }
}

// MARK: - General

struct GeneralPane: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var state = AppState.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                PaneHeader(title: "General", subtitle: "Inkling checks English as you type in any app — and stays silent for Czech.", pane: .general)
            }
            Section("Status") {
                Toggle("Check my writing", isOn: $prefs.isEnabled)
                if prefs.isPaused, let until = prefs.pausedUntil {
                    LabeledContent("Paused until") {
                        HStack {
                            Text(until.formatted(date: .omitted, time: .shortened))
                            Button("Resume") { prefs.pause(for: nil) }
                        }
                    }
                }
                LabeledContent("Accessibility access") {
                    if state.trusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(Ink.mint)
                    } else {
                        Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                    }
                }
            }
            Section("English") {
                Picker("Spelling", selection: $prefs.dialect) {
                    ForEach(EnglishDialect.allCases) { d in
                        Text("\(d.flag)  \(d.label)").tag(d)
                    }
                }
            }
            Section("While typing") {
                Toggle("Show the suggestion badge in text fields", isOn: $prefs.showBadge)
                LabeledContent("Review all suggestions") {
                    Text("⌃ ⌥ I").font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Section {
                Text(DeepExplainer.isAvailable
                     ? "Deeper explanations are written by Apple’s on-device model. Nothing is sent anywhere."
                     : "Turn on Apple Intelligence in System Settings to get deeper explanations — generated on this Mac.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("“Explain more” with Apple Intelligence")
            }
            Section("System") {
                Toggle("Open Inkling at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section {
                Text("Grammar engine: Harper (Apache-2.0) with Inkling’s coach rules for common learner mistakes.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}

struct PaneHeader: View {
    let title: String
    let subtitle: String
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: pane.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pane.tint.gradient))
                .shadow(color: pane.tint.opacity(0.35), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Checks

struct ChecksPane: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                PaneHeader(title: "Checks", subtitle: "Choose what Inkling looks for.", pane: .checks)
            }
            Section("What to check") {
                CategoryToggle(category: .spelling, title: "Spelling & typos", isOn: $prefs.checkSpelling)
                CategoryToggle(category: .grammar, title: "Grammar & word choice", isOn: $prefs.checkGrammar)
                CategoryToggle(category: .punctuation, title: "Punctuation & capitals", isOn: $prefs.checkPunctuation)
                CategoryToggle(category: .clarity, title: "Clarity & style", isOn: $prefs.checkClarity)
            }
            Section {
                Toggle(isOn: $prefs.coach) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Common learner mistakes")
                        Text("Catches “I am agree”, “since 3 years”, “informations”, “explain me”, “make a photo”…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $prefs.aiSuggestions) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("✨ AI grammar & fluency")
                        Text(AIProofreader.isAvailable
                             ? "Word order, agreement and natural phrasing, checked by Apple’s on-device model. Nothing leaves this Mac."
                             : "Needs Apple Intelligence — turn it on in System Settings.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!AIProofreader.isAvailable)
            } header: {
                Text("Coach")
            }
            Section {
                if prefs.disabledRules.isEmpty {
                    Text("No rules turned off.").foregroundStyle(.secondary)
                } else {
                    ForEach(prefs.disabledRules, id: \.self) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Lessons.title(forRule: rule))
                                Text(rule).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Turn on") {
                                withAnimation { prefs.disabledRules.removeAll { $0 == rule } }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Turned-off rules")
            } footer: {
                HStack {
                    Spacer()
                    Button("Restore defaults") { prefs.disabledRules = Preferences.defaultDisabledRules }
                        .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct CategoryToggle: View {
    let category: IssueCategory
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Squiggle(amplitude: 1.4, wavelength: 5)
                    .stroke(category.color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 22, height: 6)
                Text(title)
            }
        }
    }
}

// MARK: - Lessons

struct LessonsPane: View {
    @ObservedObject var router: SettingsRouter
    @ObservedObject private var progress = ProgressStore.shared
    @State private var query = ""
    @State private var filter = 0
    @State private var selection: String?

    struct Item: Identifiable, Hashable {
        let id: String
        let lesson: Lesson
        let category: IssueCategory
    }

    private var allItems: [Item] {
        var items = GrammarEngine.coachLessons.map {
            Item(id: $0.rule, lesson: $0.lesson, category: IssueCategory(kind: $0.kind, severity: "error", rule: $0.rule))
        }
        let coachTitles = Set(items.map { $0.lesson.title.lowercased() })
        for (rule, lesson) in Lessons.curated.sorted(by: { $0.key < $1.key }) where !coachTitles.contains(lesson.title.lowercased()) {
            items.append(Item(id: rule, lesson: lesson, category: .grammar))
        }
        return items
    }

    private var counts: [String: Int] {
        Dictionary(uniqueKeysWithValues: progress.topRules(days: 90, limit: 200).map { ($0.rule, $0.count) })
    }

    private var items: [Item] {
        let c = counts
        var list = allItems
        switch filter {
        case 1: list = list.filter { (c[$0.id] ?? 0) > 0 }
        default: break
        }
        if !query.isEmpty {
            let q = query.lowercased()
            list = list.filter { ($0.lesson.title + $0.lesson.explanation + $0.lesson.right.joined() + $0.lesson.wrong.joined()).lowercased().contains(q) }
        }
        return list.sorted { (c[$0.id] ?? 0, $1.lesson.title) > (c[$1.id] ?? 0, $0.lesson.title) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    TextField("Search lessons", text: $query)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $filter) {
                        Text("All").tag(0)
                        Text("My mistakes").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(12)
                List(items, selection: $selection) { item in
                    HStack(spacing: 8) {
                        Circle().fill(item.category.color).frame(width: 7, height: 7)
                        Text(item.lesson.title).lineLimit(1)
                        Spacer()
                        if let n = counts[item.id], n > 0 {
                            Text("\(n)×").font(.caption.weight(.semibold)).foregroundStyle(Ink.coral)
                        }
                    }
                    .tag(item.id)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 230, idealWidth: 260, maxWidth: 320)

            ScrollView {
                if let id = selection, let item = allItems.first(where: { $0.id == id }) {
                    LessonDetail(item: item, count: counts[id] ?? 0)
                        .padding(28)
                        .id(id)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                } else {
                    VStack(spacing: 12) {
                        InklingMark(size: 64)
                        Text("Pick a lesson").font(.title3.weight(.semibold))
                        Text("\(allItems.count) bite-sized English lessons.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                }
            }
            .frame(minWidth: 380)
            .animation(Ink.spring, value: selection)
        }
        .onAppear {
            if let rule = router.focusRule {
                selection = rule
                router.focusRule = nil
            } else if selection == nil {
                selection = items.first?.id
            }
        }
    }
}

struct LessonDetail: View {
    let item: LessonsPane.Item
    let count: Int
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                CategoryPill(category: item.category)
                if count > 0 {
                    Text("Seen \(count)× in your writing")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Ink.coral)
                }
            }
            Text(item.lesson.title)
                .font(.system(size: 28, weight: .bold, design: .serif))
            Text(item.lesson.explanation)
                .font(.system(size: 15))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

            if !item.lesson.wrong.isEmpty || !item.lesson.right.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(item.lesson.wrong, id: \.self) { ExampleRow(text: $0, good: false).scaleEffect(1.15, anchor: .leading) }
                    ForEach(item.lesson.right, id: \.self) { ExampleRow(text: $0, good: true).scaleEffect(1.15, anchor: .leading) }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(item.category.color.opacity(0.07)))
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }
}

// MARK: - Progress

struct ProgressPane: View {
    @ObservedObject var router: SettingsRouter
    @ObservedObject private var progress = ProgressStore.shared
    @State private var confirmReset = false
    @State private var animate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(title: "Progress", subtitle: "Only counts of mistake types are kept — never your text.", pane: .progress)

                HStack(spacing: 12) {
                    StatTile(value: progress.todayFixed, label: "fixed today", symbol: "checkmark.seal", tint: Ink.mint)
                    StatTile(value: progress.streak, label: "day streak", symbol: "flame", tint: Ink.coral)
                    StatTile(value: progress.totalFixed, label: "fixed all-time", symbol: "trophy", tint: Ink.amber)
                }

                card("Last 14 days") {
                    let series = progress.series(days: 14)
                    Chart {
                        ForEach(series, id: \.date) { d in
                            BarMark(x: .value("Day", d.date, unit: .day), y: .value("Spotted", animate ? d.seen : 0))
                                .foregroundStyle(Ink.blueprint.opacity(0.35))
                                .cornerRadius(4)
                            BarMark(x: .value("Day", d.date, unit: .day), y: .value("Fixed", animate ? d.fixed : 0))
                                .foregroundStyle(Ink.mint.gradient)
                                .cornerRadius(4)
                        }
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                    .frame(height: 170)
                    HStack(spacing: 14) {
                        Label("Spotted", systemImage: "circle.fill").foregroundStyle(Ink.blueprint.opacity(0.5))
                        Label("Fixed", systemImage: "circle.fill").foregroundStyle(Ink.mint)
                    }
                    .font(.caption)
                }

                HStack(alignment: .top, spacing: 16) {
                    card("Where mistakes happen") {
                        let totals = progress.categoryTotals(days: 30)
                        if totals.isEmpty {
                            EmptyHint(text: "Start writing in English and this fills up.")
                        } else {
                            Chart(IssueCategory.allCases.filter { (totals[$0] ?? 0) > 0 }) { c in
                                SectorMark(angle: .value("Count", animate ? (totals[c] ?? 0) : 0), innerRadius: .ratio(0.62), angularInset: 2)
                                    .foregroundStyle(c.color)
                                    .cornerRadius(4)
                            }
                            .frame(height: 150)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(IssueCategory.allCases.filter { (totals[$0] ?? 0) > 0 }) { c in
                                    HStack {
                                        Circle().fill(c.color).frame(width: 7, height: 7)
                                        Text(c.title).font(.caption)
                                        Spacer()
                                        Text("\(totals[c] ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    card("Most frequent (30 days)") {
                        let top = progress.topRules(days: 30, limit: 6)
                        if top.isEmpty {
                            EmptyHint(text: "Your most common mistakes will appear here, with a lesson for each.")
                        } else {
                            let maxCount = top.first?.count ?? 1
                            VStack(alignment: .leading, spacing: 9) {
                                ForEach(top, id: \.rule) { item in
                                    Button {
                                        router.focusRule = item.rule
                                        router.pane = .lessons
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(Lessons.title(forRule: item.rule)).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                                Spacer()
                                                Text("\(item.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                            }
                                            GeometryReader { geo in
                                                Capsule().fill(.primary.opacity(0.06))
                                                    .overlay(alignment: .leading) {
                                                        Capsule().fill(Ink.brand)
                                                            .frame(width: animate ? geo.size.width * CGFloat(item.count) / CGFloat(maxCount) : 0)
                                                    }
                                            }
                                            .frame(height: 5)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Reset progress…", role: .destructive) { confirmReset = true }
                        .controlSize(.small)
                }
            }
            .padding(24)
        }
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.1)) { animate = true } }
        .confirmationDialog("Reset all progress?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { progress.reset() }
        } message: {
            Text("This clears the mistake counts used for your stats and focus lessons.")
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.06), lineWidth: 0.6))
    }
}

struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Dictionary

struct DictionaryPane: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var newWord = ""
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(title: "Dictionary", subtitle: "Names, brands and words you want Inkling to accept.", pane: .dictionary)
            HStack {
                TextField("Add a word…", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .buttonStyle(PrimaryButtonStyle(tint: IssueCategory.wordChoice.color, compact: true))
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if prefs.userWords.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "character.book.closed").font(.system(size: 34)).foregroundStyle(.tertiary)
                    Text("Your dictionary is empty").font(.headline)
                    Text("Tip: hover a flagged name and choose “Add to dictionary”.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextField("Filter", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                List {
                    ForEach(prefs.userWords.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { word in
                        HStack {
                            Text(word).font(.system(.body, design: .serif))
                            Spacer()
                            Button {
                                withAnimation { prefs.userWords.removeAll { $0 == word } }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("\(prefs.userWords.count) word\(prefs.userWords.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(24)
    }

    private func add() {
        let w = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        withAnimation { prefs.addWord(w) }
        newWord = ""
    }
}

// MARK: - Apps

struct AppsPane: View {
    @ObservedObject private var prefs = Preferences.shared

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.processIdentifier != getpid() }
            .filter { !prefs.isExcluded($0.bundleIdentifier) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(title: "Apps", subtitle: "Inkling stays out of these apps (code editors and terminals by default).", pane: .apps)
            HStack {
                Menu("Add an app…") {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                            if let id = app.bundleIdentifier { withAnimation { prefs.excludedApps.append(id) } }
                        }
                    }
                }
                .fixedSize()
                Spacer()
                Button("Restore defaults") { prefs.excludedApps = Preferences.defaultExcludedApps }
                    .controlSize(.small)
            }
            List {
                ForEach(prefs.excludedApps, id: \.self) { id in
                    HStack(spacing: 10) {
                        AppIconView(bundleID: id)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(AppIconView.name(for: id))
                            Text(id.hasSuffix(".") ? "\(id)* (all apps from this developer)" : id).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button {
                            withAnimation { prefs.excludedApps.removeAll { $0 == id } }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(24)
    }
}

struct AppIconView: View {
    let bundleID: String
    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 26, height: 26)
        } else {
            Image(systemName: "app.dashed").font(.system(size: 20)).foregroundStyle(.tertiary).frame(width: 26, height: 26)
        }
    }

    static func name(for id: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        if id.hasPrefix("com.jetbrains") { return "JetBrains IDEs" }
        return id
    }
}

// MARK: - Privacy

struct PrivacyPane: View {
    @State private var confirmErase = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneHeader(title: "Privacy", subtitle: "Your writing is yours. It never leaves this Mac.", pane: .privacy)
                PrivacyRow(symbol: "desktopcomputer", tint: Ink.blueprint, title: "Everything runs on this Mac",
                           text: "The grammar engine (Harper + Inkling’s coach) is compiled into the app. There is no server, no account and no network code.")
                PrivacyRow(symbol: "eye.slash", tint: Ink.coral, title: "Nothing you write is stored",
                           text: "Inkling reads only the text field you’re typing in, keeps it in memory while you type, and forgets it when you move on. Password fields are always skipped.")
                PrivacyRow(symbol: "chart.bar", tint: Ink.mint, title: "Only counts, never content",
                           text: "Your progress is a tally of mistake *types* per day (e.g. “since vs. for: 3”). No words, sentences or app names are saved.")
                PrivacyRow(symbol: "sparkles", tint: Ink.sky, title: "Apple Intelligence stays local",
                           text: "“Explain more” uses Apple’s on-device model. The sentence goes to that local model only, on request.")
                PrivacyRow(symbol: "square.and.arrow.down", tint: Ink.amber, title: "What’s saved",
                           text: "Your settings, the words you add to your dictionary, and the mistake-type counts — in ~/Library/Application Support/Inkling and Inkling’s preferences.")

                HStack {
                    Button("Show data folder") {
                        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Inkling")
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Spacer()
                    Button("Erase all Inkling data…", role: .destructive) { confirmErase = true }
                }
                .controlSize(.small)
            }
            .padding(24)
        }
        .confirmationDialog("Erase everything Inkling saved?", isPresented: $confirmErase) {
            Button("Erase", role: .destructive) {
                ProgressStore.shared.reset()
                Preferences.shared.userWords = []
            }
        } message: {
            Text("Your progress counts and dictionary words will be deleted. Settings stay.")
        }
    }
}

struct PrivacyRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
