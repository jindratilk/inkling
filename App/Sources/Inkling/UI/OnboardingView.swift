import ServiceManagement
import SwiftUI

struct OnboardingView: View {
    let finish: () -> Void

    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var state = AppState.shared
    @State private var step = 0
    @State private var markProgress: CGFloat = 0
    @State private var launchAtLogin = true

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permission
                    default: personalise
                    }
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 40)), removal: .opacity.combined(with: .offset(x: -40))))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                StepDots(count: 3, current: step)
                    .padding(.bottom, 22)
            }
        }
        .frame(width: 560, height: 640)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: step)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.55).delay(0.2)) { markProgress = 1 }
        }
        .onChange(of: state.trusted) { _, trusted in
            if trusted, step == 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { step = 2 }
            }
        }
    }

    // MARK: steps

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)
            InklingMark(size: 96, progress: markProgress)
                .shadow(color: Ink.blueprint.opacity(0.4), radius: 24, y: 10)
            VStack(spacing: 8) {
                Text("Meet Inkling")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                Text("A quiet English tutor that lives on your Mac.\nIt fixes as you type — and tells you why.")
                    .font(.system(size: 14.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            LiveDemo()
                .padding(.horizontal, 36)
            HStack(spacing: 18) {
                Feature(symbol: "bolt.fill", text: "Instant", tint: Ink.amber)
                Feature(symbol: "lock.fill", text: "100% local", tint: Ink.mint)
                Feature(symbol: "graduationcap.fill", text: "Teaches you", tint: Ink.blueprint)
                Feature(symbol: "moon.zzz.fill", text: "Quiet in Czech", tint: Ink.coral)
            }
            Spacer(minLength: 8)
            Button {
                step = state.trusted ? 2 : 1
            } label: {
                Text("Get started").frame(minWidth: 160)
            }
            .buttonStyle(PrimaryButtonStyle(tint: Ink.blueprint))
            .keyboardShortcut(.defaultAction)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 30)
    }

    private var permission: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(Ink.blueprint.opacity(0.1)).frame(width: 120, height: 120)
                Circle().fill(Ink.blueprint.opacity(0.08)).frame(width: 160, height: 160)
                Image(systemName: state.trusted ? "checkmark.shield.fill" : "accessibility")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(state.trusted ? AnyShapeStyle(Ink.mint) : AnyShapeStyle(Ink.brand))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: state.trusted)
            }
            VStack(spacing: 10) {
                Text(state.trusted ? "You’re all set" : "Let Inkling see what you type")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .contentTransition(.opacity)
                Text("macOS asks you to allow **Accessibility** access so Inkling can read the text field you’re typing in and place suggestions next to your words.")
                    .font(.system(size: 13.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400)
            }
            VStack(alignment: .leading, spacing: 10) {
                PromiseRow(symbol: "lock.fill", text: "Text is read in memory only and never stored")
                PromiseRow(symbol: "wifi.slash", text: "No network, no account, no telemetry")
                PromiseRow(symbol: "key.slash", text: "Password fields are always ignored")
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.primary.opacity(0.04)))

            if state.trusted {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.mint)
                    .transition(.scale.combined(with: .opacity))
            } else {
                VStack(spacing: 10) {
                    Button {
                        Permissions.request()
                    } label: {
                        Text("Open Accessibility Settings").frame(minWidth: 200)
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Ink.blueprint))
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Turn on Inkling in the list — this screen updates by itself.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 40)
        .animation(Ink.spring, value: state.trusted)
    }

    private var personalise: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("Make it yours")
                .font(.system(size: 28, weight: .bold, design: .serif))
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Your English")
                HStack(spacing: 8) {
                    ForEach(EnglishDialect.allCases) { d in
                        Button {
                            withAnimation(Ink.snappy) { prefs.dialect = d }
                        } label: {
                            VStack(spacing: 4) {
                                Text(d.flag).font(.system(size: 26))
                                Text(d.label).font(.system(size: 11.5, weight: .medium, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(prefs.dialect == d ? Ink.blueprint.opacity(0.14) : Color.primary.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(prefs.dialect == d ? Ink.blueprint.opacity(0.6) : .clear, lineWidth: 1.5)
                            )
                            .scaleEffect(prefs.dialect == d ? 1.03 : 1)
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
            }
            VStack(spacing: 0) {
                OnboardToggle(title: "Learner coach", subtitle: "Catches common English learner mistakes and explains them", symbol: "graduationcap.fill", tint: Ink.blueprint, isOn: $prefs.coach)
                Divider().padding(.leading, 52)
                OnboardToggle(title: "Open at login", subtitle: "Always ready in the menu bar", symbol: "power", tint: Ink.coral, isOn: $launchAtLogin)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.primary.opacity(0.04)))

            Spacer()
            Button {
                if launchAtLogin { try? SMAppService.mainApp.register() }
                prefs.onboarded = true
                finish()
            } label: {
                Text("Start writing").frame(minWidth: 160)
            }
            .buttonStyle(PrimaryButtonStyle(tint: Ink.blueprint))
            .keyboardShortcut(.defaultAction)
            Text("Try it in Notes, Mail or Messages — Inkling lives in your menu bar.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 44)
    }
}

// MARK: - Pieces

private struct Backdrop: View {
    @State private var drift = false
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            Circle()
                .fill(Ink.blueprint.opacity(0.22))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: drift ? -150 : -110, y: drift ? -230 : -190)
            Circle()
                .fill(Ink.coral.opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: drift ? 170 : 130, y: drift ? 250 : 210)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? AnyShapeStyle(Ink.brand) : AnyShapeStyle(Color.primary.opacity(0.15)))
                    .frame(width: i == current ? 22 : 7, height: 7)
            }
        }
        .animation(Ink.spring, value: current)
    }
}

private struct Feature: View {
    let symbol: String
    let text: String
    let tint: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.13)))
            Text(text).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
        }
    }
}

private struct PromiseRow: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Ink.mint).frame(width: 18)
            Text(text).font(.system(size: 13))
        }
    }
}

private struct OnboardToggle: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().tint(Ink.blueprint)
        }
        .padding(10)
    }
}

/// A looping mini-film: a sentence with mistakes gets underlined, then fixed one by one.
struct LiveDemo: View {
    private struct Token: Identifiable {
        let id: Int
        let wrong: String
        let right: String?
        let category: IssueCategory
    }

    private let tokens: [Token] = [
        Token(id: 0, wrong: "I", right: nil, category: .grammar),
        Token(id: 1, wrong: "am agree", right: "agree", category: .grammar),
        Token(id: 2, wrong: "that", right: nil, category: .grammar),
        Token(id: 3, wrong: "their", right: "there", category: .wordChoice),
        Token(id: 4, wrong: "is", right: nil, category: .grammar),
        Token(id: 5, wrong: "an", right: "a", category: .grammar),
        Token(id: 6, wrong: "big", right: nil, category: .grammar),
        Token(id: 7, wrong: "problme.", right: "problem.", category: .spelling),
    ]

    @State private var flagged: Set<Int> = []
    @State private var fixed: Set<Int> = []
    @State private var focus: Int?
    @State private var loop: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(tokens) { t in
                    word(t)
                }
            }
            .font(.system(size: 19, design: .serif))
            .padding(.horizontal, 20)
            .padding(.top, 40)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.background.opacity(0.7))
                .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.06), lineWidth: 0.6))
        .onAppear { start() }
        .onDisappear { loop?.cancel() }
    }

    private func word(_ t: Token) -> some View {
        let isFixed = fixed.contains(t.id)
        let isFlagged = flagged.contains(t.id) && !isFixed
        return Text(isFixed ? (t.right ?? t.wrong) : t.wrong)
            .foregroundStyle(.primary)
            .contentTransition(.interpolate)
            .background(alignment: .bottom) {
                ZStack {
                    Squiggle(amplitude: 1.4, wavelength: 5.2)
                        .trim(from: 0, to: isFlagged ? 1 : 0)
                        .stroke(t.category.color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                        .frame(height: 6)
                    Capsule()
                        .fill(Ink.mint)
                        .frame(height: 2)
                        .scaleEffect(x: isFixed ? 1 : 0, anchor: .leading)
                        .opacity(isFixed && focus == t.id ? 1 : 0)
                }
                .offset(y: 5)
            }
            .overlay(alignment: .top) {
                if focus == t.id, let right = t.right {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                        Text(right).font(.system(size: 13, weight: .semibold, design: .serif)).foregroundStyle(t.category.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .inklingSurface(cornerRadius: 9)
                    .fixedSize()
                    .offset(y: -32)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.45), value: isFlagged)
            .animation(Ink.spring, value: isFixed)
    }

    private func start() {
        loop?.cancel()
        loop = Task { @MainActor in
            while !Task.isCancelled {
                flagged = []
                fixed = []
                focus = nil
                try? await Task.sleep(for: .milliseconds(700))
                for t in tokens where t.right != nil {
                    flagged.insert(t.id)
                    try? await Task.sleep(for: .milliseconds(260))
                }
                try? await Task.sleep(for: .milliseconds(700))
                for t in tokens where t.right != nil {
                    withAnimation(Ink.spring) { focus = t.id }
                    try? await Task.sleep(for: .milliseconds(650))
                    withAnimation(Ink.spring) { _ = fixed.insert(t.id) }
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation(Ink.spring) { focus = nil }
                    try? await Task.sleep(for: .milliseconds(180))
                }
                try? await Task.sleep(for: .milliseconds(2200))
            }
        }
    }
}
