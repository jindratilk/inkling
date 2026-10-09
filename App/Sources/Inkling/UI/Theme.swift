import AppKit
import SwiftUI

enum Ink {
    /// Blueprint blue — the brand colour.
    static let blueprint = Color(red: 0.12, green: 0.37, blue: 0.75)   // #1F5FBF
    static let sky = Color(red: 0.30, green: 0.56, blue: 0.92)         // #4D8FEA
    static let deep = Color(red: 0.05, green: 0.23, blue: 0.51)        // #0E3A82
    static let coral = Color(red: 1.00, green: 0.42, blue: 0.42)
    static let amber = Color(red: 1.00, green: 0.71, blue: 0.28)
    static let mint = Color(red: 0.19, green: 0.80, blue: 0.53)

    static let brand = LinearGradient(colors: [sky, blueprint, deep],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    static let drop = LinearGradient(colors: [coral, amber], startPoint: .bottomLeading, endPoint: .topTrailing)

    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.78)
    /// Transparent room around floating surfaces so their shadows are never clipped
    /// by the window edge. Clicks in this margin pass through to the app below.
    static let shadowPad: CGFloat = 40
    static let snappy = Animation.spring(response: 0.24, dampingFraction: 0.82)
}

// MARK: - Shapes

/// A sine wave — the signature underline.
struct Squiggle: Shape {
    var amplitude: CGFloat = 1.6
    var wavelength: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midY
        let step: CGFloat = 0.75
        var x: CGFloat = rect.minX
        p.move(to: CGPoint(x: x, y: mid))
        while x <= rect.maxX {
            let y = mid + sin((x - rect.minX) / wavelength * 2 * .pi) * amplitude
            p.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        return p
    }
}

struct InkDrop: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let radius = r.width / 2
        let center = CGPoint(x: r.midX, y: r.maxY - radius)
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: center.y),
                   control1: CGPoint(x: r.midX + r.width * 0.12, y: r.minY + r.height * 0.28),
                   control2: CGPoint(x: r.maxX, y: center.y - r.width * 0.42))
        p.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.minX, y: center.y - r.width * 0.42),
                   control2: CGPoint(x: r.midX - r.width * 0.12, y: r.minY + r.height * 0.28))
        p.closeSubpath()
        return p
    }
}

// MARK: - Logo

/// A typographic serif "i".
struct SerifI: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width * 0.36          // stem width
        let cx = r.midX
        let footH = r.height * 0.075
        let serifH = r.height * 0.07
        let stemTop = r.minY
        // stem
        p.addRoundedRect(in: CGRect(x: cx - w / 2, y: stemTop, width: w, height: r.height - footH * 0.5),
                         cornerSize: CGSize(width: w * 0.08, height: w * 0.08))
        // top-left flag serif
        p.addRoundedRect(in: CGRect(x: cx - w / 2 - w * 0.42, y: stemTop, width: w * 0.6, height: serifH),
                         cornerSize: CGSize(width: serifH * 0.3, height: serifH * 0.3))
        // foot
        p.addRoundedRect(in: CGRect(x: r.minX, y: r.maxY - footH, width: r.width, height: footH),
                         cornerSize: CGSize(width: footH * 0.35, height: footH * 0.35))
        return p
    }
}

/// The Inkling mark: ink on paper — a serif "i" whose dot is a drop of ink,
/// over a red-pen squiggle.
struct InklingMark: View {
    var size: CGFloat = 64
    /// 0…1 — lets callers animate the drop falling and the squiggle drawing in.
    var progress: CGFloat = 1
    var glow = true

    static let ink = LinearGradient(colors: [Color(red: 0.18, green: 0.45, blue: 0.86), Color(red: 0.05, green: 0.23, blue: 0.51)],
                                    startPoint: .top, endPoint: .bottom)
    static let paper = LinearGradient(colors: [Color(red: 1.0, green: 0.99, blue: 0.97), Color(red: 0.95, green: 0.93, blue: 0.89)],
                                      startPoint: .top, endPoint: .bottom)

    var body: some View {
        let s = size
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.235, style: .continuous)
                .fill(Self.paper)
            // faint ruled lines
            if s >= 48 {
                VStack(spacing: s * 0.155) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle().fill(Ink.blueprint.opacity(0.10)).frame(height: max(0.5, s * 0.006))
                    }
                }
                .padding(.horizontal, s * 0.0)
                .offset(y: s * 0.06)
                .clipShape(RoundedRectangle(cornerRadius: s * 0.235, style: .continuous))
            }
            RoundedRectangle(cornerRadius: s * 0.235, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white, .black.opacity(0.10)], startPoint: .top, endPoint: .bottom), lineWidth: max(0.5, s * 0.01))

            // the i
            SerifI()
                .fill(Self.ink)
                .frame(width: s * 0.30, height: s * 0.38)
                .shadow(color: Ink.deep.opacity(0.25), radius: s * 0.012, y: s * 0.008)
                .offset(y: s * 0.085)

            // ink-drop dot
            InkDrop()
                .fill(Self.ink)
                .overlay(
                    InkDrop().fill(RadialGradient(colors: [.white.opacity(0.65), .clear], center: UnitPoint(x: 0.36, y: 0.66), startRadius: 0, endRadius: s * 0.05))
                )
                .frame(width: s * 0.14, height: s * 0.18)
                .shadow(color: Ink.blueprint.opacity(glow ? 0.35 : 0), radius: s * 0.03, y: s * 0.01)
                .offset(y: -s * 0.245 - (1 - progress) * s * 0.22)
                .opacity(Double(min(1, progress * 2)))

            // red-pen squiggle
            Squiggle(amplitude: s * 0.02, wavelength: s * 0.125)
                .trim(from: 0, to: progress)
                .stroke(Ink.drop, style: StrokeStyle(lineWidth: s * 0.034, lineCap: .round, lineJoin: .round))
                .frame(width: s * 0.46, height: s * 0.06)
                .offset(y: s * 0.335)
        }
        .frame(width: s, height: s)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Ink.blueprint
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration, tint: tint, compact: compact)
    }

    private struct PrimaryButton: View {
        let configuration: Configuration
        let tint: Color
        let compact: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, compact ? 11 : 14)
                .padding(.vertical, compact ? 5 : 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.12), tint], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                        .shadow(color: tint.opacity(hovering ? 0.55 : 0.32), radius: hovering ? 9 : 5, y: hovering ? 3 : 2)
                )
                .brightness(configuration.isPressed ? -0.06 : (hovering ? 0.04 : 0))
                .scaleEffect(configuration.isPressed ? 0.95 : (hovering ? 1.03 : 1))
                .animation(Ink.snappy, value: configuration.isPressed)
                .animation(Ink.snappy, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

struct GhostButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        GhostButton(configuration: configuration, compact: compact)
    }

    private struct GhostButton: View {
        let configuration: Configuration
        let compact: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, compact ? 9 : 12)
                .padding(.vertical, compact ? 5 : 7)
                .background(Capsule(style: .continuous).fill(.primary.opacity(hovering ? 0.08 : 0)))
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(Ink.snappy, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// A plain button that gently reacts to hover and press.
struct SoftButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8
    func makeBody(configuration: Configuration) -> some View {
        SoftButton(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct SoftButton: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        @State private var hovering = false
        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.primary.opacity(configuration.isPressed ? 0.1 : (hovering ? 0.06 : 0))))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(Ink.snappy, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Bits

struct CategoryPill: View {
    let category: IssueCategory
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(category.color).frame(width: 6, height: 6)
                .shadow(color: category.color.opacity(0.7), radius: 3)
            Text(category.title)
                .font(.system(size: compact ? 10.5 : 11, weight: .semibold, design: .rounded))
                .foregroundStyle(category.color.mix(with: .primary, by: 0.25))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(category.color.opacity(0.13)))
    }
}

extension View {
    /// Floating glass surface used by the card, review list and badge.
    func inklingSurface(cornerRadius: CGFloat = 18) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.background.opacity(0.55))
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 0.6)
            }
    }

    func shimmering(active: Bool) -> some View {
        modifier(Shimmer(active: active))
    }
}

struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: phase * geo.size.width * 1.5)
                            .blendMode(.plusLighter)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
                    }
                }
            }
    }
}

/// Animated count that rolls its digits.
struct RollingNumber: View {
    let value: Int
    var font: Font = .system(size: 22, weight: .bold, design: .rounded)

    var body: some View {
        Text("\(value)")
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(value)))
            .animation(Ink.spring, value: value)
    }
}
