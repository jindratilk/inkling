import SwiftUI

final class BadgeModel: ObservableObject {
    @Published var count = 0
    @Published var category: IssueCategory = .spelling
    @Published var reviewOpen = false
    /// Increments when new issues appear — drives the pulse ring.
    @Published var pulse = 0
    /// The on-device AI is reading your text.
    @Published var thinking = false
}

/// The little orb that sits in the corner of the text field.
struct BadgeView: View {
    @ObservedObject var model: BadgeModel
    var onTap: () -> Void

    @State private var hovering = false
    @State private var dimmed = false
    @State private var ring = true
    @State private var spin = false

    private let size: CGFloat = 22
    /// Window side: room for the pulse ring, hover scale and shadow.
    static let window: CGFloat = 52

    var body: some View {
        ZStack {
            // pulse ring
            Circle()
                .stroke(model.category.color, lineWidth: 2)
                .frame(width: size, height: size)
                .scaleEffect(ring ? 1.75 : 1)
                .opacity(ring ? 0 : 0.7)

            if model.thinking {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(AngularGradient(colors: [Ink.sky.opacity(0), Ink.blueprint], center: .center), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: size + 7, height: size + 7)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true } }
                    .onDisappear { spin = false }
                    .transition(.opacity)
            }

            Circle()
                .fill(model.count > 0
                      ? AnyShapeStyle(LinearGradient(colors: [model.category.color.mix(with: .white, by: 0.18), model.category.color], startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(.background))
                .overlay(Circle().strokeBorder(.white.opacity(model.count > 0 ? 0.35 : 0.0), lineWidth: 0.6))
                .glassEffect(.regular, in: Circle())
                .shadow(color: (model.count > 0 ? model.category.color : .black).opacity(hovering ? 0.5 : 0.25), radius: hovering ? 6 : 3, y: 1)
                .frame(width: size, height: size)

            if model.count > 0 {
                Text("\(model.count)")
                    .font(.system(size: model.count > 9 ? 9.5 : 11, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(model.count)))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Ink.mint)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .frame(width: BadgeView.window, height: BadgeView.window)
        .scaleEffect(hovering ? 1.14 : (model.reviewOpen ? 1.08 : 1))
        .opacity(dimmed && !hovering && !model.reviewOpen ? 0.4 : 1)
        .animation(Ink.spring, value: model.count)
        .animation(.easeOut(duration: 0.25), value: model.thinking)
        .animation(Ink.snappy, value: hovering)
        .animation(.easeInOut(duration: 0.5), value: dimmed)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .onTapGesture { onTap() }
        .help(model.count > 0 ? "\(model.count) suggestion\(model.count == 1 ? "" : "s") — click to review (⌃⌥I)" : "Looks good")
        .onChange(of: model.pulse) { _, _ in firePulse() }
        .onChange(of: model.count) { _, newValue in scheduleDim(newValue) }
        .onAppear { scheduleDim(model.count) }
    }

    private func firePulse() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { ring = false }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.75)) { ring = true }
        }
    }

    private func scheduleDim(_ count: Int) {
        dimmed = false
        guard count == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if model.count == 0 { dimmed = true }
        }
    }
}
