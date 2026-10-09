import SwiftUI

struct MenuBarView: View {
    let actions: MenuActions
    let close: () -> Void

    @ObservedObject private var state = AppState.shared
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var progress = ProgressStore.shared
    @State private var appeared = false

    private var status: AppState.Status { state.status(prefs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            StatusCard(status: status, state: state, prefs: prefs, openOnboarding: { close(); actions.openOnboarding() })
            todayStats
            focusCard
            footer
        }
        .padding(16)
        .frame(width: 344)
        .onAppear {
            appeared = false
            withAnimation(Ink.spring.delay(0.05)) { appeared = true }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            InklingMark(size: 34, progress: appeared ? 1 : 0.2)
                .animation(.spring(response: 0.6, dampingFraction: 0.6), value: appeared)
            VStack(alignment: .leading, spacing: 1) {
                Text("Inkling")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Your private English tutor")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { prefs.isEnabled && !prefs.isPaused }, set: { on in
                withAnimation(Ink.spring) {
                    prefs.isEnabled = on
                    if on { prefs.pausedUntil = nil }
                }
            }))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .tint(Ink.blueprint)
        }
    }

    private var todayStats: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Today")
            HStack(spacing: 8) {
                StatTile(value: progress.todaySeen, label: "spotted", symbol: "eye", tint: Ink.blueprint)
                StatTile(value: progress.todayFixed, label: "fixed", symbol: "checkmark.seal", tint: Ink.mint)
                StatTile(value: progress.streak, label: progress.streak == 1 ? "day streak" : "day streak", symbol: "flame", tint: Ink.coral)
            }
        }
    }

    @ViewBuilder
    private var focusCard: some View {
        let top = progress.topRules(days: 30, limit: 1).first
        let rule = top?.rule
        let lesson = rule.flatMap { Lessons.lesson(forRule: $0) } ?? lessonOfTheDay
        if let lesson {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(top != nil ? "Your focus this month" : "Lesson of the day")
                Button {
                    close()
                    actions.openSettings(.lessons)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(lesson.title)
                                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            Spacer()
                            if let top {
                                Text("\(top.count)×")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Ink.coral)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Ink.coral.opacity(0.12)))
                            }
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        Text(lesson.explanation)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        if let right = lesson.right.first {
                            ExampleRow(text: right, good: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Ink.blueprint.opacity(0.09), Ink.sky.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.blueprint.opacity(0.14), lineWidth: 0.6))
                }
                .buttonStyle(PressScaleStyle())
            }
        }
    }

    /// Stable for the whole day, so the panel never changes size while open.
    private var lessonOfTheDay: Lesson? {
        let all = GrammarEngine.coachLessons
        guard !all.isEmpty else { return nil }
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        return all[day % all.count].lesson
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Menu {
                    Button("For 30 minutes") { prefs.pause(for: 1800) }
                    Button("For 1 hour") { prefs.pause(for: 3600) }
                    Button("Until tomorrow") {
                        let tomorrow = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
                        prefs.pause(for: tomorrow.timeIntervalSinceNow)
                    }
                    if prefs.isPaused {
                        Divider()
                        Button("Resume now") { prefs.pause(for: nil) }
                    }
                } label: {
                    Label(prefs.isPaused ? "Paused" : "Pause", systemImage: prefs.isPaused ? "pause.circle.fill" : "pause.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()

                if let id = state.bundleID, let name = state.appName {
                    let excluded = prefs.isExcluded(id)
                    Button {
                        actions.toggleExclusion(id)
                    } label: {
                        Label(excluded ? "Enable in \(name)" : "Off in \(name)", systemImage: excluded ? "checkmark.circle" : "nosign")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button {
                    close()
                    actions.openSettings(.general)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Settings")
            }

            HStack {
                Label("100% on this Mac · nothing stored", systemImage: "lock.fill")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { actions.quit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
    }
}

struct StatTile: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: value)
            RollingNumber(value: value, font: .system(size: 21, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(hovering ? 0.12 : 0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.12), lineWidth: 0.6))
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(Ink.snappy, value: hovering)
        .onHover { hovering = $0 }
    }
}

/// What Inkling is doing right now, with a living indicator.
struct StatusCard: View {
    let status: AppState.Status
    @ObservedObject var state: AppState
    @ObservedObject var prefs: Preferences
    let openOnboarding: () -> Void
    @State private var breathe = false

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                if let icon = state.appIcon, status != .needsPermission {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Ink.amber)
                        .frame(width: 30, height: 30)
                }
                Circle()
                    .fill(dotColor)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
                    .scaleEffect(breathe && status == .checking ? 1.15 : 1)
                    .offset(x: 12, y: 12)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if status == .needsPermission {
                Button("Grant", action: openOnboarding)
                    .buttonStyle(PrimaryButtonStyle(tint: Ink.amber, compact: true))
            } else if status == .checking, state.issueCount > 0 {
                HStack(spacing: 3) {
                    ForEach(IssueCategory.allCases.filter { (state.categoryCounts[$0] ?? 0) > 0 }) { c in
                        Circle().fill(c.color).frame(width: 7, height: 7)
                    }
                }
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.primary.opacity(0.045)))
        .animation(Ink.spring, value: status)
        .animation(Ink.spring, value: state.issueCount)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    private var dotColor: Color {
        switch status {
        case .checking: state.issueCount > 0 ? IssueCategory.grammar.color : Ink.mint
        case .quietCzech, .idle: .gray
        case .needsPermission: Ink.amber
        default: .gray.opacity(0.6)
        }
    }

    private var appName: String { state.appName ?? "this app" }

    private var title: String {
        switch status {
        case .needsPermission: "Needs Accessibility access"
        case .off: "Inkling is off"
        case .paused: "Paused"
        case .excluded: "Off in \(appName)"
        case .idle: "Ready when you type"
        case .quietCzech: "Czech detected — staying quiet"
        case .checking:
            state.issueCount == 0 ? "All good in \(appName)" : "\(state.issueCount) suggestion\(state.issueCount == 1 ? "" : "s") in \(appName)"
        }
    }

    private var subtitle: String {
        switch status {
        case .needsPermission: "So Inkling can read the field you’re typing in."
        case .off: "Turn it on with the switch above."
        case .paused:
            if let until = prefs.pausedUntil { "Back at \(until.formatted(date: .omitted, time: .shortened))" } else { "" }
        case .excluded: "You turned Inkling off for this app."
        case .idle: "Click into any text field and write in English."
        case .quietCzech: "Inkling only steps in for English."
        case .checking:
            state.lastCheckMicros < 1000 ? "Checked on-device in under 1 ms" : "Checked on-device in \(state.lastCheckMicros / 1000) ms"
        }
    }
}
