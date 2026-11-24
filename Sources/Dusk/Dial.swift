import SwiftUI

final class DialState: ObservableObject {
    @Published var dragging = false
    @Published var breathe = false
    var fromDisc = false
    var lastSnap: Double?
    var lastTick = -1
}

/// Rotary warmth dial: tick ring, glowing arc that grows as the screen warms,
/// dark disc with the current value. Drag around the ring to turn; tap the disc to toggle.
struct WarmthDial: View {
    @Binding var kelvin: Double
    @Binding var enabled: Bool
    let presetName: String

    @StateObject private var st = DialState()
    private let size: CGFloat = 224
    private let start = 120.0, sweep = 300.0
    private let lo = 500.0, hi = 6500.0
    private static let sun = Color(red: 1, green: 0.88, blue: 0.54)
    private static let arcColors: [Color] = [sun, .ember, Color(red: 0.95, green: 0.31, blue: 0.48), Color(red: 0.78, green: 0.12, blue: 0.2)]

    private var p: Double { (hi - kelvin) / (hi - lo) }
    private var R: CGFloat { size / 2 - 2 }
    private var Ra: CGFloat { R - 24 }
    private var Rd: CGFloat { Ra - 17 }

    var body: some View {
        ZStack {
            ticks
            ring
            glassKnob
            disc
        }
        .frame(width: size, height: size)
        .saturation(enabled ? 1 : 0)
        .opacity(enabled ? 1 : 0.55)
        .contentShape(Circle())
        .gesture(drag)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: st.dragging)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { st.breathe = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Warmth")
        .accessibilityValue("\(Int(kelvin)) Kelvin, \(presetName)")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: kelvin = max(kelvin - 300, lo)
            case .decrement: kelvin = min(kelvin + 300, hi)
            @unknown default: break
            }
        }
        .accessibilityAction(named: enabled ? "Turn off" : "Turn on") { enabled.toggle() }
    }

    private var ticks: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let cur = Int((p * 60).rounded())
            for i in 0...60 {
                let f = Double(i) / 60
                let a = (start + sweep * f) * .pi / 180
                let major = i % 10 == 0
                let here = i == cur
                let r1 = R - (here ? 15 : major ? 12 : 7)
                var path = Path()
                path.move(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
                path.addLine(to: CGPoint(x: c.x + cos(a) * R, y: c.y + sin(a) * R))
                let lit = f <= p + 0.0001
                let color: Color = lit ? (major ? Self.sun : .ember.opacity(0.9)) : .white.opacity(major ? 0.28 : 0.14)
                ctx.stroke(path, with: .color(here ? .white : color), style: StrokeStyle(lineWidth: here ? 2.6 : major ? 2 : 1.2, lineCap: .round))
            }
        }
    }

    private var ring: some View {
        let arc = AngularGradient(colors: Self.arcColors, center: .center, startAngle: .degrees(0), endAngle: .degrees(sweep))
        let to = max(p, 0.004) * sweep / 360
        return ZStack {
            Circle().trim(from: 0, to: sweep / 360)
                .stroke(.white.opacity(0.07), style: StrokeStyle(lineWidth: 13, lineCap: .round))
            Circle().trim(from: 0, to: to)
                .stroke(arc, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .blur(radius: 9)
                .opacity(st.breathe ? 0.95 : 0.55)
            Circle().trim(from: 0, to: to)
                .stroke(arc, style: StrokeStyle(lineWidth: st.dragging ? 15 : 13, lineCap: .round))
        }
        .frame(width: Ra * 2, height: Ra * 2)
        .rotationEffect(.degrees(start))
    }

    /// Glass bead riding the end of the arc.
    private var glassKnob: some View {
        let a = (start + sweep * p) * .pi / 180
        let d: CGFloat = 24
        return ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(.white.opacity(0.16))
            Circle().fill(RadialGradient(colors: [Color.warm(kelvin).opacity(0.55), Color.warm(kelvin).opacity(0.1)], center: .init(x: 0.5, y: 0.75), startRadius: 0, endRadius: 14))
            Circle().fill(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom))
                .padding(1.5)
            Ellipse().fill(.white.opacity(0.85))
                .frame(width: d * 0.42, height: d * 0.16)
                .blur(radius: 0.6)
                .offset(y: -d * 0.27)
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.15)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .frame(width: d, height: d)
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
        .scaleEffect(st.dragging && !st.fromDisc ? 1.2 : 1)
        .offset(x: cos(a) * Ra, y: sin(a) * Ra)
        .allowsHitTesting(false)
    }

    private var disc: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.17), Color(white: 0.06)], center: .init(x: 0.42, y: 0.35), startRadius: 0, endRadius: Rd * 1.1))
                .overlay(Circle().fill(RadialGradient(colors: [Color.warm(kelvin).opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: Rd)))
                .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 3).blur(radius: 3).offset(y: 2).mask(Circle()))
                .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                .frame(width: Rd * 2, height: Rd * 2)
                .scaleEffect(st.dragging && st.fromDisc ? 0.97 : 1)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: String(Int(kelvin)))
                        .font(.serif(52))
                        .contentTransition(.numericText(value: kelvin))
                    Text("K").font(.serif(22)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                Text(enabled ? presetName : "Paused")
                    .font(.geist(11, .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .contentTransition(.interpolate)
            }
            .animation(.snappy, value: Int(kelvin))
            .allowsHitTesting(false)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let c = CGPoint(x: size / 2, y: size / 2)
                if !st.dragging {
                    st.dragging = true
                    st.fromDisc = hypot(v.startLocation.x - c.x, v.startLocation.y - c.y) < Rd - 4
                    if !st.fromDisc { haptic(.generic) }
                }
                guard !st.fromDisc, enabled else { return }
                var rel = (atan2(v.location.y - c.y, v.location.x - c.x) * 180 / .pi - start)
                    .truncatingRemainder(dividingBy: 360)
                if rel < 0 { rel += 360 }
                if rel > sweep { rel = rel > sweep + (360 - sweep) / 2 ? 0 : sweep }
                var k = hi - rel / sweep * (hi - lo)
                if let s = Preset.all.map(\.kelvin).min(by: { abs($0 - k) < abs($1 - k) }), abs(s - k) < 120 {
                    k = s
                    if st.lastSnap != s { st.lastSnap = s; haptic() }
                } else {
                    st.lastSnap = nil
                }
                kelvin = (k / 10).rounded() * 10
                let tick = Int(((hi - kelvin) / (hi - lo) * 60).rounded())
                if tick != st.lastTick, st.lastSnap == nil || st.lastSnap != kelvin {
                    st.lastTick = tick
                    Sound.shared.tick(Double(tick) / 60)
                }
            }
            .onEnded { v in
                if st.fromDisc && hypot(v.translation.width, v.translation.height) < 4 {
                    enabled.toggle()
                    haptic(.levelChange)
                    Sound.shared.toggle(enabled)
                }
                st.dragging = false
            }
    }
}
