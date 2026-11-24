import SwiftUI

final class Flag: ObservableObject { @Published var on = false }

let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)

extension Color {
    static let ember = Color(red: 1, green: 0.604, blue: 0.302)
    static func warm(_ kelvin: Double) -> Color {
        let c = Display.rgb(kelvin: kelvin)
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}

func haptic(_ p: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
    NSHapticFeedbackManager.defaultPerformer.perform(p, performanceTime: .now)
}

final class SliderState: ObservableObject {
    @Published var dragging = false
    @Published var hovering = false
    var lastSnap: Double?
}

/// Thick recessed track, a living "sun" knob that takes the current colour, magnetic snap
/// points with trackpad haptics, and a floating value bubble while dragging or hovering.
struct GlowSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let colors: [Color]
    let tint: Color
    var fill = false
    var snaps: [Double] = []
    var name = ""
    var label: (Double) -> String = { "\(Int($0))" }
    var icon: (Double) -> String = { _ in "sun.max.fill" }
    var rays = false

    @StateObject private var st = SliderState()
    private let knob: CGFloat = 26
    private let track: CGFloat = 12
    private var span: Double { range.upperBound - range.lowerBound }

    var body: some View {
        GeometryReader { g in
            let w = max(g.size.width - knob, 1)
            let t = CGFloat((value - range.lowerBound) / span)
            let cx = knob / 2 + w * t
            let cy = g.size.height / 2
            let grad = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)

            ZStack(alignment: .topLeading) {
                // recessed track
                Capsule()
                    .fill(.black.opacity(0.28))
                    .overlay(Capsule().fill(grad).opacity(fill ? 0.16 : 0.95))
                    .overlay(alignment: .leading) {
                        if fill {
                            Capsule().fill(grad).frame(width: max(cx + knob * 0.2, track))
                        }
                    }
                    .overlay(Capsule().stroke(.black.opacity(0.45), lineWidth: 1.5).blur(radius: 1.2).offset(y: 1).mask(Capsule()))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                    .frame(width: g.size.width, height: st.dragging ? track + 4 : track)
                    .position(x: g.size.width / 2, y: cy)

                // snap ticks
                ForEach(snaps, id: \.self) { s in
                    let hit = abs(s - value) < span * 0.001
                    Circle()
                        .fill(.white.opacity(hit ? 0.95 : 0.4))
                        .frame(width: hit ? 5 : 3.5, height: hit ? 5 : 3.5)
                        .position(x: knob / 2 + w * CGFloat((s - range.lowerBound) / span), y: cy)
                }

                // knob
                ZStack {
                    if rays {
                        Circle()
                            .strokeBorder(tint.opacity(0.9), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [0.5, 4.2]))
                            .frame(width: knob + 10, height: knob + 10)
                            .rotationEffect(.degrees(t * 270))
                            .opacity(st.dragging || st.hovering ? 1 : 0.55)
                    }
                    Circle().fill(.white)
                        .frame(width: knob, height: knob)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1.5)
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.9), tint], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 11))
                        .frame(width: knob - 8, height: knob - 8)
                    Image(systemName: icon(value))
                        .font(.geist(9, .heavy))
                        .foregroundStyle(.black.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                }
                .scaleEffect(st.dragging ? 1.16 : 1)
                .position(x: cx, y: cy)

                // value bubble
                Text(label(value))
                    .font(.geist(11, .semibold).monospacedDigit())
                    .contentTransition(.numericText(value: value))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .fixedSize()
                    .scaleEffect(st.dragging || st.hovering ? 1 : 0.6, anchor: .bottom)
                    .opacity(st.dragging || st.hovering ? 1 : 0)
                    .position(x: min(max(cx, 24), g.size.width - 24), y: cy - 28)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onHover { st.hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let first = !st.dragging
                        if first { st.dragging = true; haptic(.generic) }
                        let p = Double(min(max((v.location.x - knob / 2) / w, 0), 1))
                        var nv = range.lowerBound + p * span
                        if let s = snaps.min(by: { abs($0 - nv) < abs($1 - nv) }), abs(s - nv) < span * 0.025 {
                            nv = s
                            if st.lastSnap != s { st.lastSnap = s; haptic() }
                        } else {
                            st.lastSnap = nil
                        }
                        if first {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { value = nv }
                        } else {
                            value = nv
                        }
                    }
                    .onEnded { _ in st.dragging = false }
            )
        }
        .frame(height: 34)
        .animation(.spring(response: 0.32, dampingFraction: 0.62), value: st.dragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: st.hovering)
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityValue(label(value))
        .accessibilityAdjustableAction { dir in
            let step = span / 20
            switch dir {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
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
                    if next != isOn { isOn = next; haptic(.levelChange) }
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
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .background {
                ZStack {
                    Capsule().fill(.primary.opacity(0.06))
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
                Text(sub).font(.geist(11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            GlowSwitch(isOn: $on, tint: tint, name: title)
        }
    }
}
