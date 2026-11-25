import AppKit
import SwiftUI

/// "Sundown": a short stage play on every screen.
/// On: the Dusk sun sinks behind a horizon, velvet curtains with a starry lining sway shut over it,
/// the seam flares, and the curtain burns away into rising embers, leaving the warm screen.
/// Off: the starry curtain fades in, parts from the middle, and the sun rises through the gap in a bloom.
struct SweepView: View {
    let start: Date
    let on: Bool
    static let duration = 2.2

    private static func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    private static func seg(_ x: Double, _ a: Double, _ b: Double) -> Double { min(max((x - a) / (b - a), 0), 1) }
    private static func rnd(_ i: Int, _ k: Int) -> Double { // stable pseudo-random 0..1
        let v = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
        return v - floor(v)
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, sz in
                let t = tl.date.timeIntervalSince(start)
                let x = min(max(t / Self.duration, 0), 1)
                let w = sz.width, h = sz.height
                let S = Self.self

                // Timeline
                let close = on ? S.ease(S.seg(x, 0.08, 0.58)) : 1 - S.ease(S.seg(x, 0.18, 0.78))
                let veil = on ? 1 - S.seg(x, 0.7, 0.95) : S.seg(x, 0, 0.14) * (1 - S.seg(x, 0.82, 1))
                let sunP = on ? S.ease(S.seg(x, 0, 0.62)) : 1 - S.ease(S.seg(x, 0.25, 0.85)) // 0 = up, 1 = set
                let stars = on ? S.seg(x, 0.25, 0.6) : 1 - S.seg(x, 0.3, 0.7)
                let flare = on ? sin(.pi * S.seg(x, 0.52, 0.8)) : 0
                let bloom = on ? 0 : sin(.pi * S.seg(x, 0.6, 1))
                let embers = on ? S.seg(x, 0.62, 1) : 0

                // 1. Sun and horizon, seen through the gap.
                let horizon = h * 0.6
                let R = min(w, h) * 0.15
                let sunY = horizon - R * 0.55 + R * 1.7 * sunP
                let sunA = veil * (1 - S.seg(sunP, 0.85, 1))
                if sunA > 0 {
                    let c = CGPoint(x: w / 2, y: sunY)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - R * 3, y: c.y - R * 3, width: R * 6, height: R * 6)),
                             with: .radialGradient(Gradient(colors: [Color.ember.opacity(0.4 * sunA), Color.rose.opacity(0.12 * sunA), .clear]),
                                                   center: c, startRadius: R * 0.8, endRadius: R * 3))
                    var sky = ctx
                    sky.clip(to: Path(CGRect(x: 0, y: 0, width: w, height: horizon)))
                    // The slit sun: a disc cut by bands that thicken toward the horizon, like the app icon.
                    var disc = Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
                    for (i, (dy, th)) in [(0.12, 0.05), (0.36, 0.08), (0.6, 0.11), (0.84, 0.15)].enumerated() {
                        let drift = sin(t * 2 + Double(i)) * R * 0.02
                        disc.addRect(CGRect(x: c.x - R * 1.2, y: c.y + R * dy + drift, width: R * 2.4, height: R * th))
                    }
                    sky.fill(disc, with: .linearGradient(Gradient(colors: [Color.sun.opacity(sunA), Color.ember.opacity(sunA), Color.rose.opacity(sunA)]),
                                                         startPoint: CGPoint(x: c.x, y: c.y - R), endPoint: CGPoint(x: c.x, y: c.y + R)),
                             style: FillStyle(eoFill: true))
                    let line = Path(CGRect(x: 0, y: horizon - 0.75, width: w, height: 1.5))
                    ctx.fill(Path(CGRect(x: 0, y: horizon - 30, width: w, height: 60)),
                             with: .linearGradient(Gradient(colors: [.clear, Color.ember.opacity(0.22 * sunA), .clear]),
                                                   startPoint: CGPoint(x: 0, y: horizon - 30), endPoint: CGPoint(x: 0, y: horizon + 30)))
                    ctx.fill(line, with: .color(Color.sun.opacity(0.7 * sunA)))
                }

                // 2. Velvet curtains with a starry lining and a wavy, swinging hem.
                let half = w / 2 * close
                if half > 0.5, veil > 0 {
                    let sway = 10 + 30 * sin(.pi * min(close, 1 - close) * 2)
                    func wave(_ y: Double, _ ph: Double) -> Double {
                        let hang = 0.25 + 0.75 * y / h
                        return sway * hang * (0.6 * sin(y / 90 + t * 5 + ph) + 0.4 * sin(y / 37 - t * 3.3 + ph * 2))
                    }
                    let ys = Array(stride(from: 0.0, through: h, by: 8)) + [h]
                    for left in [true, false] {
                        let ph = left ? 0.0 : 1.7
                        let ex = { (y: Double) in left ? half + wave(y, ph) : w - half - wave(y, ph) }
                        var edge = Path()
                        edge.addLines(ys.map { CGPoint(x: ex($0), y: $0) })
                        var cloth = edge
                        cloth.addLine(to: CGPoint(x: left ? -60 : w + 60, y: h))
                        cloth.addLine(to: CGPoint(x: left ? -60 : w + 60, y: 0))
                        cloth.closeSubpath()

                        ctx.fill(cloth, with: .linearGradient(
                            Gradient(colors: [Color.night.opacity(0.88 * veil), Color.indigo.opacity(0.8 * veil), Color.rose.opacity(0.72 * veil)]),
                            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                        var inner = ctx
                        inner.clip(to: cloth)
                        let n = 9, pleat = half / Double(n)
                        for i in 0..<n {
                            let f = Double(i) / Double(n)
                            var p = Path()
                            p.addLines(ys.map { y in
                                CGPoint(x: left ? pleat * Double(i) + wave(y, ph) * f : w - pleat * Double(i) - wave(y, ph) * f, y: y)
                            })
                            inner.stroke(p, with: .color(.black.opacity(0.2 * veil)), lineWidth: max(pleat * 0.45, 2))
                        }
                        // Stars woven into the upper lining, pinned to the cloth so they travel with it.
                        if stars > 0 {
                            for i in 0..<70 {
                                let u = S.rnd(i, left ? 1 : 2), v = S.rnd(i, 3)
                                let y = v * v * h * 0.62
                                let px = left ? u * half + wave(y, ph) * u : w - u * half - wave(y, ph) * u
                                let tw = 0.55 + 0.45 * sin(t * (3 + S.rnd(i, 4) * 4) + Double(i))
                                let a = stars * veil * tw * (0.5 + 0.5 * S.rnd(i, 5))
                                let r = 0.7 + 1.6 * S.rnd(i, 6)
                                inner.fill(Path(ellipseIn: CGRect(x: px - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(a)))
                                if S.rnd(i, 7) > 0.85 {
                                    inner.fill(Path(ellipseIn: CGRect(x: px - r * 4, y: y - r * 4, width: r * 8, height: r * 8)),
                                               with: .radialGradient(Gradient(colors: [Color.sun.opacity(a * 0.5), .clear]),
                                                                     center: CGPoint(x: px, y: y), startRadius: 0, endRadius: r * 4))
                                }
                            }
                        }
                        ctx.stroke(edge, with: .color(Color.ember.opacity(0.16 * veil)), lineWidth: 40)
                        ctx.stroke(edge, with: .color(Color.ember.opacity(0.3 * veil)), lineWidth: 12)
                        ctx.stroke(edge, with: .color(Color.sun.opacity(0.85 * veil)), lineWidth: 2)
                    }
                }

                // 3. The seam flares where the curtains meet.
                if flare > 0 {
                    let fw = 220 * flare
                    ctx.fill(Path(CGRect(x: w / 2 - fw, y: 0, width: fw * 2, height: h)),
                             with: .linearGradient(Gradient(colors: [.clear, Color.ember.opacity(0.45 * flare), Color.sun.opacity(0.7 * flare), Color.ember.opacity(0.45 * flare), .clear]),
                                                   startPoint: CGPoint(x: w / 2 - fw, y: 0), endPoint: CGPoint(x: w / 2 + fw, y: 0)))
                }

                // 4. The curtain burns away into embers that drift up.
                if embers > 0, embers < 1 {
                    for i in 0..<90 {
                        let life = S.seg(embers, S.rnd(i, 8) * 0.35, 1)
                        guard life > 0, life < 1 else { continue }
                        let x0 = w / 2 + (S.rnd(i, 9) - 0.5) * w * (0.15 + 0.85 * S.rnd(i, 10))
                        let y0 = h * (0.35 + 0.65 * S.rnd(i, 11))
                        let px = x0 + sin(t * 2 + Double(i)) * 18 * life
                        let py = y0 - life * h * (0.25 + 0.3 * S.rnd(i, 12))
                        let r = 1.2 + 2.6 * S.rnd(i, 13) * (1 - life)
                        let a = sin(.pi * life)
                        ctx.fill(Path(ellipseIn: CGRect(x: px - r * 4, y: py - r * 4, width: r * 8, height: r * 8)),
                                 with: .radialGradient(Gradient(colors: [Color.ember.opacity(0.35 * a), .clear]),
                                                       center: CGPoint(x: px, y: py), startRadius: 0, endRadius: r * 4))
                        ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)), with: .color(Color.sun.opacity(0.9 * a)))
                    }
                }

                // 5. Dawn bloom as the sun clears the curtain.
                if bloom > 0 {
                    let c = CGPoint(x: w / 2, y: horizon - R)
                    ctx.fill(Path(CGRect(origin: .zero, size: sz)),
                             with: .radialGradient(Gradient(colors: [Color.sun.opacity(0.35 * bloom), Color.ember.opacity(0.12 * bloom), .clear]),
                                                   center: c, startRadius: 0, endRadius: max(w, h) * 0.7))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Click-through windows over every screen that play one sweep, then close.
enum ScreenSweep {
    private static var windows: [NSWindow] = []
    private static var token = 0

    static func play(on: Bool, only ids: Set<CGDirectDisplayID>? = nil) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        windows.forEach { $0.close() }
        let start = Date()
        windows = NSScreen.screens.filter { s in
            guard let ids else { return true }
            return (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID).map(ids.contains) ?? false
        }.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.contentView = NSHostingView(rootView: SweepView(start: start, on: on))
            w.setFrame(screen.frame, display: false)
            w.orderFrontRegardless()
            return w
        }
        token += 1
        let mine = token
        DispatchQueue.main.asyncAfter(deadline: .now() + SweepView.duration + 0.05) {
            guard mine == token else { return }
            windows.forEach { $0.close() }
            windows = []
        }
    }
}
