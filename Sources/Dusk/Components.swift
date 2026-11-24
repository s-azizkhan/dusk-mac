import SwiftUI

final class Flag: ObservableObject { @Published var on = false }

let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)

extension Color {
    static let ember = Color(red: 1, green: 0.604, blue: 0.302)
    static let rose = Color(red: 0.949, green: 0.314, blue: 0.482)
    static let sun = Color(red: 1, green: 0.878, blue: 0.541)
    static let night = Color(red: 0.055, green: 0.039, blue: 0.165)
    static let indigo = Color(red: 0.165, green: 0.114, blue: 0.4)
    static func warm(_ kelvin: Double) -> Color {
        let c = Display.rgb(kelvin: kelvin)
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}

func haptic(_ p: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
    NSHapticFeedbackManager.defaultPerformer.perform(p, performanceTime: .now)
    switch p {
    case .alignment: Sound.shared.snap()
    case .generic: Sound.shared.press()
    default: break
    }
}

final class PressState: ObservableObject { @Published var pressed = false }

/// Day/night switch: a starry night track that floods with colour when on, a squishy knob
/// that stretches on press, follows a flick, and morphs its symbol.
struct GlowSwitch: View {
    @Binding var isOn: Bool
    let tint: Color
    var name = ""
    var onIcon: String? = nil
    var offIcon: String? = nil

    @StateObject private var p = PressState()
    private let w: CGFloat = 46, h: CGFloat = 26, k: CGFloat = 22

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(LinearGradient(colors: [Color(red: 0.1, green: 0.08, blue: 0.24), Color(red: 0.17, green: 0.12, blue: 0.36)], startPoint: .leading, endPoint: .trailing))
                .overlay(Capsule().fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing)).opacity(isOn ? 1 : 0))
                .overlay(alignment: .trailing) {
                    ZStack {
                        Circle().fill(.white).frame(width: 2, height: 2).offset(x: -6, y: -5)
                        Circle().fill(.white).frame(width: 1.5, height: 1.5).offset(x: -13, y: 4)
                        Circle().fill(.white).frame(width: 2.5, height: 2.5).offset(x: -4, y: 5)
                    }
                    .frame(width: 22, height: h)
                    .opacity(isOn ? 0 : 0.75)
                    .scaleEffect(isOn ? 0.3 : 1)
                }
                .overlay(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.35)).frame(width: 10, height: 2).padding(.leading, 9)
                        .opacity(isOn ? 1 : 0)
                }
                .overlay(Capsule().stroke(.black.opacity(0.45), lineWidth: 1.5).blur(radius: 1.2).offset(y: 1).mask(Capsule()))
                .overlay(Capsule().strokeBorder(.white.opacity(isOn ? 0.3 : 0.12), lineWidth: 0.5))

            Capsule()
                .fill(.white)
                .frame(width: p.pressed ? k + 7 : k, height: k)
                .overlay {
                    if let s = isOn ? onIcon : offIcon {
                        Image(systemName: s)
                            .font(.geist(10, .bold))
                            .foregroundStyle(isOn ? tint : Color(red: 0.35, green: 0.3, blue: 0.6))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 2.5, y: 1.5)
                .padding(2)
        }
        .frame(width: w, height: h)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !p.pressed { p.pressed = true } }
                .onEnded { v in
                    p.pressed = false
                    let next = abs(v.translation.width) > 8 ? v.translation.width > 0 : !isOn
                    if next != isOn { isOn = next; haptic(.levelChange); Sound.shared.toggle(next) }
                }
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.66), value: isOn)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: p.pressed)
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isOn.toggle() }
    }
}

struct Chip: View {
    let preset: Preset
    let selected: Bool
    let ns: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(Color.warm(preset.kelvin)).frame(width: 9, height: 9)
                    .shadow(color: Color.warm(preset.kelvin).opacity(0.8), radius: selected ? 4 : 0)
                Text(preset.name).font(.geist(12, .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(.white.opacity(selected ? 1 : 0.82))
            .background {
                ZStack {
                    Capsule().fill(.white.opacity(0.1))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.8))
                    if selected {
                        Capsule().fill(Color.warm(preset.kelvin).opacity(0.28))
                            .overlay(Capsule().strokeBorder(Color.warm(preset.kelvin).opacity(0.6), lineWidth: 1))
                            .matchedGeometryEffect(id: "sel", in: ns)
                    }
                }
            }
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in if down { haptic(.generic) } }
    }
}

struct ToggleRow: View {
    let icon: String
    let title: String
    let sub: String
    @Binding var on: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.geist(13, .semibold))
                .foregroundStyle(on ? tint : .secondary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(on ? 0.2 : 0.07)))
                .symbolEffect(.bounce, value: on)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.geist(13, .medium))
                Text(sub).font(.geist(11)).foregroundStyle(.white.opacity(0.68))
            }
            Spacer(minLength: 4)
            GlowSwitch(isOn: $on, tint: tint, name: title)
        }
    }
}

final class BarState: ObservableObject {
    @Published var dragging = false
    @Published var hover: Int?
    var last = -1
}

/// Brightness as a rising staircase of light bars. Click or drag anywhere; each step ticks
/// with a rising pitch, every 25% gives a firmer click. Hover previews where you'll land.
struct BrightnessBars: View {
    @Binding var value: Double
    let tint: Color
    @StateObject private var st = BarState()
    private let n = 20
    private let gap: CGFloat = 3

    private var lit: Int { Int((value * Double(n)).rounded()) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min.fill")
                .font(.system(size: 11 + 7 * value, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: value)
            GeometryReader { g in
                let bw = (g.size.width - gap * CGFloat(n - 1)) / CGFloat(n)
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(0..<n, id: \.self) { i in
                        let on = i < lit
                        let h = 8 + (g.size.height - 8) * CGFloat(i + 1) / CGFloat(n)
                        let isHover = st.hover == i
                        RoundedRectangle(cornerRadius: min(bw / 2, 3), style: .continuous)
                            .fill(on ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(Color.white.opacity(isHover ? 0.28 : 0.14)))
                            .overlay(RoundedRectangle(cornerRadius: min(bw / 2, 3), style: .continuous)
                                .strokeBorder(.white.opacity(isHover ? 0.6 : 0), lineWidth: 1))
                            .frame(width: bw, height: h)
                            .scaleEffect(y: st.dragging && i == lit - 1 ? 1.15 : 1, anchor: .bottom)
                            .animation(.spring(response: 0.32, dampingFraction: 0.62).delay(Double(i) * 0.006), value: on)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): st.hover = index(p.x, bw)
                    case .ended: st.hover = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in st.dragging = true; set(index(v.location.x, bw)) }
                        .onEnded { _ in st.dragging = false }
                )
            }
            .frame(height: 36)
            Text(verbatim: "\(Int((value * 100).rounded()))%")
                .font(.geistMono(12, .medium))
                .foregroundStyle(.white.opacity(0.85))
                .contentTransition(.numericText(value: value))
                .frame(width: 38, alignment: .trailing)
                .animation(.snappy, value: value)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: st.dragging)
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: set(lit)
            case .decrement: set(lit - 2)
            @unknown default: break
            }
        }
    }

    private func index(_ x: CGFloat, _ bw: CGFloat) -> Int { min(max(Int(x / (bw + gap)), 0), n - 1) }

    private func set(_ i: Int) {
        let k = min(max(i, 0), n - 1)
        if k != st.last {
            st.last = k
            if (k + 1) % 5 == 0 { haptic() } else { Sound.shared.tick(Double(k) / Double(n - 1)) }
        }
        value = Double(k + 1) / Double(n)
    }
}

/// Makes the MenuBarExtra window transparent with continuous rounded corners.
struct RoundedWindow: NSViewRepresentable {
    var radius: CGFloat
    func makeNSView(context: Context) -> NSView { Probe(radius: radius) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        let radius: CGFloat
        init(radius: CGFloat) { self.radius = radius; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window, let cv = w.contentView else { return }
            w.isOpaque = false
            w.backgroundColor = .clear
            for v in [cv, cv.superview].compactMap({ $0 }) {
                v.wantsLayer = true
                v.layer?.cornerRadius = radius
                v.layer?.cornerCurve = .continuous
                v.layer?.masksToBounds = true
            }
            w.invalidateShadow()
        }
    }
}

/// Wraps children into centered rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, width: proposal.width ?? .infinity)
        let h = rows.map { $0.h }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map { $0.w }.max() ?? 0, height: h)
    }

    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = b.minY
        for r in rows(subviews, width: b.width) {
            var x = b.minX + (b.width - r.w) / 2
            for i in r.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += r.h + spacing
        }
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], w: CGFloat, h: CGFloat)] {
        var out: [(items: [Int], w: CGFloat, h: CGFloat)] = []
        var cur: [Int] = [], w: CGFloat = 0, h: CGFloat = 0
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            if !cur.isEmpty && w + spacing + s.width > width {
                out.append((cur, w, h)); cur = []; w = 0; h = 0
            }
            w += (cur.isEmpty ? 0 : spacing) + s.width
            h = max(h, s.height)
            cur.append(i)
        }
        if !cur.isEmpty { out.append((cur, w, h)) }
        return out
    }
}

final class Measured: ObservableObject { @Published var height: CGFloat = 0 }

/// Frosted glass card with a soft top highlight.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.black.opacity(0.22)))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

extension View {
    func glassCard(radius: CGFloat = 16) -> some View { modifier(GlassCard(radius: radius)) }
}

/// Fine film grain, generated once and tiled.
enum Grain {
    static let image: NSImage = {
        let n = 96
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let v = UInt8.random(in: 0...255)
            px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v; px[i * 4 + 3] = 255
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: n * 4, bitsPerPixel: 32)!
        px.withUnsafeBufferPointer { memcpy(rep.bitmapData!, $0.baseAddress!, n * n * 4) }
        let img = NSImage(size: NSSize(width: n, height: n))
        img.addRepresentation(rep)
        return img
    }()
}

/// Slow warm dust motes drifting upward, like light at sunset. Only runs while visible.
struct DustLayer: View {
    let tint: Color
    var count = 26

    private func r(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i * 127 + k * 311)) * 43758.5453
        return x - floor(x)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let speed = 4 + r(i, 1) * 10
                    let y = size.height - (r(i, 2) * size.height + t * speed).truncatingRemainder(dividingBy: size.height + 20) + 10
                    let x = r(i, 3) * size.width + sin(t * (0.2 + r(i, 4) * 0.3) + Double(i)) * 10
                    let d = 1 + r(i, 5) * 2.2
                    let a = 0.15 + 0.35 * (0.5 + 0.5 * sin(t * (0.6 + r(i, 6)) + Double(i)))
                    let rect = CGRect(x: x - d * 2, y: y - d * 2, width: d * 4, height: d * 4)
                    ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(a * 0.25)))
                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: d * 1.5, dy: d * 1.5)), with: .color(.white.opacity(a)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
