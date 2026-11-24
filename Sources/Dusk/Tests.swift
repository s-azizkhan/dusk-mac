import AppKit
import SwiftUI

/// Backlight as an oscilloscope trace: a flat line when it's steady, a scrolling square wave when it pulses.
struct WaveGraphic: View {
    let duty: Double? // nil = steady light
    let tint: Color
    @ObservedObject private var panel = PanelState.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !panel.visible)) { tl in
            Canvas { ctx, sz in
                let t = tl.date.timeIntervalSinceReferenceDate
                let top = 6.0, bottom = sz.height - 14
                for i in 1..<4 { // faint grid
                    let y = top + (bottom - top) * Double(i) / 4
                    ctx.fill(Path(CGRect(x: 0, y: y, width: sz.width, height: 0.5)), with: .color(.white.opacity(0.06)))
                }
                var p = Path()
                if let duty {
                    let period = 26.0, shift = (t * 60).truncatingRemainder(dividingBy: period)
                    var x = -shift
                    p.move(to: CGPoint(x: x, y: top))
                    while x < sz.width {
                        let on = period * duty
                        p.addLine(to: CGPoint(x: x + on, y: top)); p.addLine(to: CGPoint(x: x + on, y: bottom))
                        p.addLine(to: CGPoint(x: x + period, y: bottom)); p.addLine(to: CGPoint(x: x + period, y: top))
                        x += period
                    }
                } else {
                    p.move(to: CGPoint(x: 0, y: top))
                    p.addLine(to: CGPoint(x: sz.width, y: top))
                }
                ctx.stroke(p, with: .color(tint.opacity(0.3)), lineWidth: 5)
                ctx.stroke(p, with: .color(tint), lineWidth: 1.5)
                ctx.draw(Text(duty == nil ? "Steady light" : "Pulsing light").font(.geist(9.5, .medium)).foregroundColor(.white.opacity(0.6)),
                         at: CGPoint(x: 0, y: sz.height), anchor: .bottomLeading)
                ctx.draw(Text("backlight").font(.geist(9.5)).foregroundColor(.white.opacity(0.35)),
                         at: CGPoint(x: sz.width, y: sz.height), anchor: .bottomTrailing)
            }
        }
        .frame(height: 50)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.28)))
    }
}

/// A patch of dark pixels, zoomed in. With dithering they flicker between neighbour shades; without it they hold still.
struct DitherGraphic: View {
    let shimmer: Bool
    @ObservedObject private var panel = PanelState.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !panel.visible || !shimmer)) { tl in
            Canvas { ctx, sz in
                let cols = 18, rows = 4
                let cell = min(sz.width / Double(cols), (sz.height - 14) / Double(rows))
                let frame = Int(tl.date.timeIntervalSinceReferenceDate * 12)
                for r in 0..<rows {
                    for c in 0..<cols {
                        let base = 0.12 + 0.3 * Double(c) / Double(cols - 1)
                        var v = (base * 8).rounded(.down) / 8 // what the panel can really show: steps
                        if shimmer {
                            let n = sin(Double(c * 31 + r * 17 + frame * 7) * 12.9898) * 43758.5453
                            if n - floor(n) < (base * 8 - (base * 8).rounded(.down)) { v += 1.0 / 8 }
                        }
                        ctx.fill(Path(roundedRect: CGRect(x: Double(c) * cell, y: Double(r) * cell, width: cell - 1, height: cell - 1), cornerRadius: 1.5),
                                 with: .color(Color(white: v)))
                    }
                }
                ctx.draw(Text(shimmer ? "Pixels shimmer" : "Pixels hold still").font(.geist(9.5, .medium)).foregroundColor(.white.opacity(0.6)),
                         at: CGPoint(x: 0, y: sz.height), anchor: .bottomLeading)
                ctx.draw(Text("zoomed in").font(.geist(9.5)).foregroundColor(.white.opacity(0.35)),
                         at: CGPoint(x: sz.width, y: sz.height), anchor: .bottomTrailing)
            }
        }
        .frame(height: 64)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.28)))
    }
}

// MARK: Full-screen tests

private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { ScreenTest.close() }
}

enum ScreenTest {
    private static var window: NSWindow?
    private static var onClose: (() -> Void)?

    static func open<V: View>(_ view: V, onClose: (() -> Void)? = nil) {
        close()
        self.onClose = onClose
        guard let screen = NSScreen.main else { return }
        let w = KeyWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.level = .screenSaver
        w.backgroundColor = .black
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: view.onTapGesture { close() })
        w.setFrame(screen.frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    static func close() {
        window?.close(); window = nil
        onClose?(); onClose = nil
    }
}

private struct TestCaption: View {
    let title: String
    let lines: [String]
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.serif(34)).foregroundStyle(.white)
            ForEach(lines, id: \.self) { Text($0).font(.geist(15)).foregroundStyle(.white.opacity(0.7)) }
            Text("Click or press Esc to close").font(.geist(12)).foregroundStyle(.white.opacity(0.4)).padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 60)
    }
}

/// Phantom-array test: a bright bar racing across black. Let your eyes sweep past it.
/// Steady light leaves one smooth blur; a pulsing backlight leaves a row of separate copies.
struct FlickerScreenTest: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            TimelineView(.animation) { tl in
                Canvas { ctx, sz in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let x = (t * 2600).truncatingRemainder(dividingBy: sz.width + 200) - 100
                    for (i, y) in [0.45, 0.6, 0.75].enumerated() {
                        let xx = i == 1 ? sz.width - x : x
                        ctx.fill(Path(CGRect(x: xx - 3, y: sz.height * y - 40, width: 6, height: 80)), with: .color(.white))
                    }
                }
            }
            TestCaption(title: "Flicker test", lines: [
                "Look at the middle of the screen and quickly move your eyes left and right past the white bars.",
                "One smooth streak: steady light. A row of separate bars: the backlight is pulsing.",
            ])
        }
        .ignoresSafeArea()
    }
}

final class DitherFlag: ObservableObject {
    @Published var on: Bool
    init(_ on: Bool) { self.on = on }
}

/// Dark gradient where dithering is easiest to see. Flip it live and compare.
struct DitherScreenTest: View {
    @ObservedObject var c: Controller
    @StateObject private var disabled: DitherFlag

    init(c: Controller) {
        self.c = c
        _disabled = StateObject(wrappedValue: DitherFlag(c.antiDither))
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(white: 0.0), Color(white: 0.14)], startPoint: .leading, endPoint: .trailing)
            VStack {
                TestCaption(title: "Dithering test", lines: [
                    "Get close to the screen and look at the dark gradient.",
                    "Dithering on: the edges between shades softly crawl. Off: they sit still as clean steps.",
                ])
                Spacer()
                Button {
                    disabled.on.toggle()
                    Display.setDithering(disabled: disabled.on)
                } label: {
                    Text(disabled.on ? "Dithering is off. Turn it on to compare" : "Dithering is on. Turn it off to compare")
                        .font(.geist(15, .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 80)
            }
        }
        .ignoresSafeArea()
    }
}
