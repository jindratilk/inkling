import SwiftUI

final class ReviewModel: ObservableObject {
    @Published var lints: [Lint] = []
    @Published var micros = 0
    @Published var aiAvailable = false
    // Improve (DeepL Write–style)
    @Published var tone: WritingTone = .natural
    @Published var improveSource = ""
    @Published var improved: String?
    @Published var improving = false
    @Published var improveFailed = false
}

struct ReviewActions {
    var accept: (Lint, String) -> Void
    var dismiss: (Lint) -> Void
    var hover: (UUID?) -> Void
    var fixAll: ([Lint]) -> Void
    var close: () -> Void
    var improve: (WritingTone) -> Void
    var applyImprove: () -> Void
}

/// All suggestions for the current field, opened from the badge (or ⌃⌥I).
struct ReviewListView: View {
    @ObservedObject var model: ReviewModel
    let actions: ReviewActions

    @State private var expanded: UUID?
    @State private var appeared = false
    @State private var contentHeight: CGFloat = 0

    private var spellingFixes: [Lint] { model.lints.filter { $0.isSpelling && !$0.suggestions.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Rectangle().fill(.primary.opacity(0.07)).frame(height: 0.5)

            ScrollView {
                VStack(spacing: 6) {
                    if model.aiAvailable {
                        ImproveCard(model: model, actions: actions)
                    }
                    if model.lints.isEmpty {
                        AllClearView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, model.aiAvailable ? 10 : 26)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                    ForEach(model.lints) { lint in
                        ReviewRow(lint: lint, expanded: expanded == lint.id, actions: actions) {
                            withAnimation(Ink.spring) { expanded = expanded == lint.id ? nil : lint.id }
                        }
                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }
                .padding(8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 60), 480))

            Rectangle().fill(.primary.opacity(0.07)).frame(height: 0.5)
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 372)
        .inklingSurface(cornerRadius: 22)
        .shadow(color: .black.opacity(0.17), radius: 18, y: 8)
        .padding(Ink.shadowPad)
        .scaleEffect(appeared ? 1 : 0.95, anchor: .bottomTrailing)
        .opacity(appeared ? 1 : 0)
        .animation(Ink.spring, value: model.lints.map(\.id))
        .animation(Ink.spring, value: model.improved)
        .onAppear { withAnimation(Ink.spring) { appeared = true } }
    }

    private var header: some View {
        titleRow
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            InklingMark(size: 26, glow: false)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    RollingNumber(value: model.lints.count, font: .system(size: 14, weight: .bold, design: .rounded))
                    Text(model.lints.count == 1 ? "suggestion" : "suggestions")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: actions.close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.primary.opacity(0.06)))
            }
            .buttonStyle(PressScaleStyle())
        }
    }

    private var summary: String {
        if model.lints.isEmpty { return "Nothing to fix — nice writing." }
        var counts: [IssueCategory: Int] = [:]
        model.lints.forEach { counts[$0.category, default: 0] += 1 }
        return IssueCategory.allCases.compactMap { c in counts[c].map { "\($0) \(c.title.lowercased())" } }.joined(separator: " · ")
    }

    private var footer: some View {
        HStack {
            if spellingFixes.count > 1 {
                Button {
                    actions.fixAll(spellingFixes)
                } label: {
                    Label("Fix all spelling (\(spellingFixes.count))", systemImage: "wand.and.stars")
                }
                .buttonStyle(PrimaryButtonStyle(tint: IssueCategory.spelling.color, compact: true))
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            Label {
                Text(model.micros < 1000 ? "On-device · <1 ms" : "On-device · \(model.micros / 1000) ms")
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
        }
    }
}

struct ReviewRow: View {
    let lint: Lint
    let expanded: Bool
    let actions: ReviewActions
    let toggle: () -> Void

    @State private var hovering = false
    @State private var whyOpen = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(lint.category.color)
                    .frame(width: 3.5)
                    .frame(maxHeight: .infinity)
                    .shadow(color: lint.category.color.opacity(0.5), radius: 3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(lint.original)
                            .font(.system(size: 14, design: .serif))
                            .strikethrough(!lint.suggestions.isEmpty, color: lint.category.color.opacity(0.8))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let s = lint.suggestions.first {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                            Text(s.isEmpty ? "remove" : s)
                                .font(.system(size: 14, weight: .semibold, design: .serif))
                                .foregroundStyle(lint.category.color.mix(with: .primary, by: 0.15))
                                .lineLimit(1)
                        }
                    }
                    Text(lint.message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 1)
                        .fixedSize(horizontal: false, vertical: expanded)
                }
                Spacer(minLength: 4)
                if let s = lint.suggestions.first, !expanded {
                    Button {
                        actions.accept(lint, s)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(hovering ? .white : lint.category.color)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(hovering ? lint.category.color : lint.category.color.opacity(0.12)))
                    }
                    .buttonStyle(PressScaleStyle())
                    .help("Accept “\(s)”")
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    LessonPanel(lesson: Lessons.lesson(for: lint), color: lint.category.color, expanded: $whyOpen)
                    HStack(spacing: 6) {
                        if let s = lint.suggestions.first {
                            Button {
                                actions.accept(lint, s)
                            } label: {
                                Label("Accept", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(PrimaryButtonStyle(tint: lint.category.color, compact: true))
                        }
                        Button("Dismiss") { actions.dismiss(lint) }
                            .buttonStyle(GhostButtonStyle(compact: true))
                    }
                }
                .padding(.leading, 13)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.primary.opacity(expanded ? 0.05 : (hovering ? 0.04 : 0)))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { h in
            hovering = h
            actions.hover(h ? lint.id : nil)
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Celebration when there's nothing left to fix.
struct AllClearView: View {
    @State private var drawn: CGFloat = 0
    @State private var pop = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Ink.mint.opacity(0.14))
                    .frame(width: 54, height: 54)
                    .scaleEffect(pop ? 1 : 0.6)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 9))
                    p.addLine(to: CGPoint(x: 7, y: 16))
                    p.addLine(to: CGPoint(x: 20, y: 2))
                }
                .trim(from: 0, to: drawn)
                .stroke(Ink.mint, style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                .frame(width: 20, height: 18)
            }
            Text("All clear")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Your English looks great here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { pop = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.12)) { drawn = 1 }
        }
    }
}


/// The AI "better version" of your text (DeepL Write–style), right at the top
/// of the suggestions list: tone chips, an inline diff and one-click Replace.
struct ImproveCard: View {
    @ObservedObject var model: ReviewModel
    let actions: ReviewActions
    @State private var expanded = false
    @State private var copied = false

    private var hasChange: Bool { model.improved.map { $0 != model.improveSource } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.brand)
                    .symbolEffect(.pulse, isActive: model.improving)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .contentTransition(.opacity)
                Spacer()
                if model.improved == model.improveSource, !model.improving {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Ink.mint)
                }
            }

            HStack(spacing: 5) {
                ForEach(WritingTone.allCases) { tone in
                    Button {
                        model.tone = tone
                        actions.improve(tone)
                    } label: {
                        Text(tone.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(model.tone == tone ? .white : .primary.opacity(0.7))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(model.tone == tone ? AnyShapeStyle(Ink.blueprint.gradient) : AnyShapeStyle(Color.primary.opacity(0.06))))
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .animation(Ink.snappy, value: model.tone)

            Group {
                if model.improving {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule().fill(.primary.opacity(0.08)).frame(width: [280, 240, 160][i], height: 9)
                        }
                    }
                    .shimmering(active: true)
                    .padding(.vertical, 2)
                } else if model.improveFailed {
                    Text("The on-device model couldn’t rewrite this right now.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else if hasChange, let improved = model.improved {
                    Text(diff(old: model.improveSource, new: improved))
                        .font(.system(size: 13))
                        .lineSpacing(2.5)
                        .lineLimit(expanded ? nil : 5)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .onTapGesture { withAnimation(Ink.spring) { expanded.toggle() } }
                    HStack(spacing: 6) {
                        Button {
                            actions.applyImprove()
                        } label: {
                            Label("Replace text", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: Ink.blueprint, compact: true))
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(improved, forType: .string)
                            withAnimation { copied = true }
                        }
                        .buttonStyle(GhostButtonStyle(compact: true))
                    }
                }
            }
            .transition(.opacity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Ink.blueprint.opacity(0.09), Ink.sky.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.blueprint.opacity(0.14), lineWidth: 0.6))
        .animation(Ink.spring, value: model.improving)
        .onChange(of: model.improved) { _, _ in copied = false }
    }

    private var title: String {
        if model.improving { return "Writing a better version…" }
        if model.improved == model.improveSource { return "Reads naturally" }
        return "Better version"
    }

    private func diff(old: String, new: String) -> AttributedString {
        var out = AttributedString()
        for seg in WordDiff.segments(old: old, new: new) {
            var piece = AttributedString(seg.text)
            switch seg.op {
            case .equal:
                break
            case .delete:
                piece.strikethroughStyle = .single
                piece.foregroundColor = IssueCategory.spelling.color.opacity(0.75)
            case .insert:
                piece.foregroundColor = Ink.blueprint
                piece.backgroundColor = Ink.blueprint.opacity(0.10)
                piece.font = .system(size: 13.5, weight: .semibold)
            }
            out += piece
        }
        return out
    }
}
