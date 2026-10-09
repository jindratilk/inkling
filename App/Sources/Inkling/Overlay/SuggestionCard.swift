import SwiftUI

struct CardActions {
    var accept: (String) -> Void
    var dismiss: () -> Void
    var ignoreRule: () -> Void
    var addToDictionary: (() -> Void)?
}

/// The card that appears when you hover an underlined word.
struct SuggestionCardView: View {
    let lint: Lint
    let sentence: String
    let actions: CardActions

    @ObservedObject private var prefs = Preferences.shared
    @StateObject private var explainer = DeepExplainer()
    @AppStorage("whyOpen") private var whyOpen = true
    @State private var appeared = false
    @State private var nudge = false
    @State private var accepted: String?

    private var lesson: Lesson { Lessons.lesson(for: lint) }
    private var color: Color { lint.category.color }
    private var showWhyExpanded: Bool { whyOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            correction
            if !lint.message.isEmpty {
                Text(lint.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            LessonPanel(lesson: lesson, color: color, expanded: $whyOpen)
            if explainer.isStreaming || !explainer.text.isEmpty || explainer.failed {
                deepExplanation
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
            footer
        }
        .padding(16)
        .frame(width: 352, alignment: .leading)
        .inklingSurface(cornerRadius: 20)
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        .shadow(color: color.opacity(0.10), radius: 6, y: 2)
        .padding(Ink.shadowPad)
        .scaleEffect(appeared ? 1 : 0.94, anchor: .top)
        .opacity(appeared ? 1 : 0)
        .blur(radius: appeared ? 0 : 5)
        .animation(Ink.spring, value: whyOpen)
        .animation(Ink.spring, value: explainer.text.isEmpty)
        .onAppear {
            // AI suggestions have no rule-based lesson — explain them straight away.
            if lint.isAI, DeepExplainer.isAvailable { explainer.explain(lint: lint, sentence: sentence) }
            withAnimation(Ink.spring) { appeared = true }
            withAnimation(Ink.spring.delay(0.08)) { nudge = true }
        }
    }

    // MARK: pieces

    private var header: some View {
        HStack(spacing: 8) {
            CategoryPill(category: lint.category)
            if lint.isAI {
                Label("AI", systemImage: "sparkles")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Ink.brand))
            }
            Text(lesson.title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var correction: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(lint.original)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .strikethrough(!lint.suggestions.isEmpty, color: color.opacity(0.9))
                    .foregroundStyle(lint.suggestions.isEmpty ? .primary : .secondary)
                    .lineLimit(2)
                if let first = lint.suggestions.first {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .offset(x: nudge ? 0 : -8)
                        .opacity(nudge ? 1 : 0)
                    SuggestionChip(text: first, color: color, primary: true, accepted: accepted == first) {
                        accept(first)
                    }
                    .offset(x: nudge ? 0 : -10)
                    .opacity(nudge ? 1 : 0)
                }
            }
            if lint.suggestions.count > 1 {
                HStack(spacing: 6) {
                    Text("or")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                    ForEach(lint.suggestions.dropFirst().prefix(3), id: \.self) { s in
                        SuggestionChip(text: s, color: color, primary: false, accepted: accepted == s) { accept(s) }
                    }
                }
            }
        }
    }

    private var deepExplanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse, isActive: explainer.isStreaming)
                Text("Apple Intelligence · on this Mac")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(LinearGradient(colors: [Ink.blueprint, Ink.sky, Ink.coral], startPoint: .leading, endPoint: .trailing))

            if explainer.failed {
                Text("The on-device model couldn’t answer right now.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            } else if explainer.text.isEmpty {
                Text("Thinking…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .shimmering(active: true)
            } else {
                Text(explainer.text)
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Ink.blueprint.opacity(0.08), Ink.coral.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let first = lint.suggestions.first {
                Button {
                    accept(first)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: accepted != nil ? "checkmark" : "checkmark.circle.fill")
                            .contentTransition(.symbolEffect(.replace))
                        Text(accepted != nil ? "Fixed" : "Accept")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(tint: accepted != nil ? Ink.mint : color, compact: true))
            }
            Button("Dismiss", action: actions.dismiss)
                .buttonStyle(GhostButtonStyle(compact: true))
            if DeepExplainer.isAvailable, !explainer.isStreaming, explainer.text.isEmpty {
                Button {
                    explainer.explain(lint: lint, sentence: sentence)
                } label: {
                    Label("Explain", systemImage: "sparkles")
                }
                .buttonStyle(GhostButtonStyle(compact: true))
                .transition(.opacity)
            }

            Spacer(minLength: 0)

            if let add = actions.addToDictionary {
                IconAction(symbol: "character.book.closed", label: "Add to dictionary", action: add)
            }
            IconAction(symbol: "nosign", label: "Turn off rule", action: actions.ignoreRule)
        }
    }

    private func accept(_ s: String) {
        guard accepted == nil else { return }
        withAnimation(Ink.snappy) { accepted = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { actions.accept(s) }
    }
}

/// A suggested replacement you can click.
struct SuggestionChip: View {
    let text: String
    let color: Color
    let primary: Bool
    var accepted = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if text.isEmpty {
                    Text("remove").italic()
                } else {
                    Text(text)
                }
            }
            .font(.system(size: primary ? 17 : 13, weight: .semibold, design: primary ? .serif : .default))
            .foregroundStyle(accepted ? Ink.mint : color.mix(with: .primary, by: 0.1))
            .padding(.horizontal, primary ? 10 : 8)
            .padding(.vertical, primary ? 4 : 3)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill((accepted ? Ink.mint : color).opacity(hovering ? 0.2 : 0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder((accepted ? Ink.mint : color).opacity(hovering ? 0.5 : 0.18), lineWidth: 1)
            )
            .shadow(color: color.opacity(hovering ? 0.3 : 0), radius: 6, y: 2)
            .offset(y: hovering ? -1 : 0)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(Ink.snappy, value: hovering)
        .animation(Ink.snappy, value: accepted)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Ink.snappy, value: configuration.isPressed)
    }
}

/// Round icon button whose label slides out on hover.
struct IconAction: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                if hovering {
                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(hovering ? .primary : .secondary)
            .padding(.horizontal, 7)
            .frame(height: 26)
            .frame(minWidth: 26)
            .background(Capsule(style: .continuous).fill(.primary.opacity(hovering ? 0.09 : 0.045)))
        }
        .buttonStyle(PressScaleStyle())
        .onHover { h in withAnimation(Ink.snappy) { hovering = h } }
        .help(label)
    }
}

/// Explanation + examples. Shared by the card and the review list.
struct LessonPanel: View {
    let lesson: Lesson
    let color: Color
    @Binding var expanded: Bool

    var hasExtras: Bool { !lesson.wrong.isEmpty || !lesson.right.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(color)
                    Text("Why?")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 9) {
                    Text(lesson.explanation)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)

                    if !lesson.wrong.isEmpty || !lesson.right.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(lesson.wrong, id: \.self) { ExampleRow(text: $0, good: false) }
                            ForEach(lesson.right, id: \.self) { ExampleRow(text: $0, good: true) }
                        }
                    }

                }
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(color.opacity(0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(color.opacity(0.12), lineWidth: 0.6)
        )
    }
}

struct ExampleRow: View {
    let text: String
    let good: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: good ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(good ? Ink.mint : IssueCategory.spelling.color)
            Text(text)
                .font(.system(size: 12.5, design: .serif))
                .italic()
                .foregroundStyle(good ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
