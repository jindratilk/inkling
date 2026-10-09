import SwiftUI

final class UnderlineModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: UUID
        var rects: [CGRect]   // panel-local, top-left origin
        var category: IssueCategory
        var hint: Bool
    }

    struct Flash: Identifiable {
        let id = UUID()
        let rects: [CGRect]
        let color: Color
    }

    @Published var items: [Item] = []
    @Published var hovered: UUID?
    @Published var flashes: [Flash] = []
    @Published var visible = true
}

struct UnderlineCanvas: View {
    @ObservedObject var model: UnderlineModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.items) { item in
                UnderlineMark(item: item, hovered: model.hovered == item.id)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 0.6, anchor: .leading))))
            }
            ForEach(model.flashes) { flash in
                ResolvedFlash(flash: flash)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(model.visible ? 1 : 0)
        .animation(.easeOut(duration: 0.16), value: model.visible)
        .allowsHitTesting(false)
    }
}

/// One underlined issue: draws itself in like ink, thickens & glows on hover.
struct UnderlineMark: View {
    let item: UnderlineModel.Item
    let hovered: Bool
    @State private var drawn: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(item.rects.enumerated()), id: \.offset) { _, r in
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(item.category.color.opacity(hovered ? 0.16 : 0))
                    .frame(width: r.width + 4, height: r.height + 2)
                    .position(x: r.midX, y: r.midY)

                line(width: r.width)
                    .frame(width: max(2, r.width), height: 6)
                    .position(x: r.midX, y: r.maxY - 1.2)
            }
        }
        .animation(Ink.snappy, value: hovered)
        .onAppear {
            withAnimation(.easeOut(duration: 0.42)) { drawn = 1 }
        }
    }

    @ViewBuilder
    private func line(width: CGFloat) -> some View {
        let color = item.category.color
        if item.hint {
            Path { p in
                p.move(to: CGPoint(x: 1, y: 3))
                p.addLine(to: CGPoint(x: max(1, width - 1), y: 3))
            }
            .trim(from: 0, to: drawn)
            .stroke(color.opacity(hovered ? 1 : 0.85), style: StrokeStyle(lineWidth: hovered ? 2.4 : 2, lineCap: .round, dash: [0.1, 3.6]))
        } else {
            Squiggle(amplitude: hovered ? 1.8 : 1.35, wavelength: 5.2)
                .trim(from: 0, to: drawn)
                .stroke(color, style: StrokeStyle(lineWidth: hovered ? 2.1 : 1.6, lineCap: .round, lineJoin: .round))
                .shadow(color: color.opacity(hovered ? 0.7 : 0), radius: 3)
        }
    }
}

/// The little celebration when a fix lands: the squiggle irons out into a
/// mint stroke that sweeps across the word and evaporates.
struct ResolvedFlash: View {
    let flash: UnderlineModel.Flash
    @State private var sweep: CGFloat = 0
    @State private var fade = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(flash.rects.enumerated()), id: \.offset) { _, r in
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Ink.mint.opacity(fade ? 0 : 0.22))
                    .frame(width: r.width + 6, height: r.height + 2)
                    .scaleEffect(x: 1, y: fade ? 1.25 : 1)
                    .position(x: r.midX, y: r.midY)

                Capsule()
                    .fill(Ink.mint)
                    .frame(width: max(2, r.width * sweep), height: 2.2)
                    .shadow(color: Ink.mint.opacity(0.8), radius: 4)
                    .position(x: r.minX + r.width * sweep / 2, y: r.maxY - 1.2)
                    .opacity(fade ? 0 : 1)
                    .offset(y: fade ? 3 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.28)) { sweep = 1 }
            withAnimation(.easeIn(duration: 0.45).delay(0.35)) { fade = true }
        }
    }
}
