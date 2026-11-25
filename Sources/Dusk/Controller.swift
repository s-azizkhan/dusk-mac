import AppKit
import ServiceManagement
import SwiftUI

struct Preset: Identifiable {
    let name: String
    let kelvin: Double
    var id: String { name }
    static let all = [
        Preset(name: "Energy", kelvin: 6000), Preset(name: "Daylight", kelvin: 5000),
        Preset(name: "Evening", kelvin: 3400), Preset(name: "Night", kelvin: 2700),
        Preset(name: "Late", kelvin: 1900), Preset(name: "Deep", kelvin: 1200),
        Preset(name: "Midnight", kelvin: 500),
    ]
}

final class Controller: ObservableObject {
    private let d = UserDefaults.standard
    private var timer: Timer?

    @Published var enabled: Bool {
        didSet {
            d.set(enabled, forKey: "enabled")
            apply()
            let start = Date()
            sweepStart = start
            ScreenSweep.play(on: enabled)
            DispatchQueue.main.asyncAfter(deadline: .now() + SweepView.duration) { [weak self] in
                if self?.sweepStart == start { self?.sweepStart = nil }
            }
        }
    }
    @Published var sweepStart: Date?
    // kelvin/brightness show the selected screen ("all" = every screen at once).
    @Published var kelvin: Double { didSet { guard !loading else { return }; store("k", kelvin); apply() } }
    @Published var brightness: Double { didSet { guard !loading else { return }; store("b", brightness); apply() } }
    @Published var screens: [Display.Screen] = []
    @Published var selected: String { didSet { d.set(selected, forKey: "selectedScreen"); load() } }
    private var looks: [String: [String: Double]]
    private var loading = false
    @Published var flickerFree: Bool { didSet { d.set(flickerFree, forKey: "flickerFree"); apply() } }
    @Published var antiDither: Bool { didSet { d.set(antiDither, forKey: "antiDither"); Display.setDithering(disabled: antiDither) } }
    @Published var scheduleOn: Bool { didSet { d.set(scheduleOn, forKey: "scheduleOn"); apply() } }
    @Published var startHour: Int { didSet { d.set(startHour, forKey: "startHour"); apply() } }
    @Published var endHour: Int { didSet { d.set(endHour, forKey: "endHour"); apply() } }
    @Published var gammaOK = true
    @Published var sounds: Bool { didSet { d.set(sounds, forKey: "sounds") } }
    @Published var launchAtLogin: Bool {
        didSet { try? (launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()) }
    }

    init() {
        // Dusk's brightness is the built-in screen's real brightness. If the backlight was left below 100%
        // (keys pressed while Dusk was closed, or first run), start from it so nothing jumps.
        let miniLED = Display.builtinIsMiniLED
        if let id = Display.builtin, let b = Backlight.get(id), b < 0.99 { d.set(max(Double(b), 0.05), forKey: "brightness") }
        d.register(defaults: ["enabled": true, "kelvin": 3400.0, "brightness": 1.0, "startHour": 20, "endHour": 7,
                              "flickerFree": !miniLED, "antiDither": true])
        looks = d.dictionary(forKey: "screens") as? [String: [String: Double]] ?? [:]
        if let id = Display.builtin, let b = Backlight.get(id), b < 0.99, looks["builtin"] != nil { looks["builtin"]?["b"] = max(Double(b), 0.05) }
        selected = d.string(forKey: "selectedScreen") ?? "all"
        enabled = d.bool(forKey: "enabled")
        kelvin = d.double(forKey: "kelvin")
        brightness = d.double(forKey: "brightness")
        flickerFree = d.bool(forKey: "flickerFree")
        antiDither = d.bool(forKey: "antiDither")
        scheduleOn = d.bool(forKey: "scheduleOn")
        startHour = d.integer(forKey: "startHour")
        endHour = d.integer(forKey: "endHour")
        sounds = d.object(forKey: "sounds") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshScreens()
        load()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.apply() }
        CGDisplayRegisterReconfigurationCallback({ _, _, ctx in
            guard let ctx else { return }
            DispatchQueue.main.async { let c = Unmanaged<Controller>.fromOpaque(ctx).takeUnretainedValue(); c.refreshScreens(); c.apply() }
        }, Unmanaged.passUnretained(self).toOpaque())
        // Light keep-alive (schedule, gamma resets by other apps). Loose tolerance lets macOS batch the wake-up.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.apply() }
        timer?.tolerance = 20
        if antiDither { Display.setDithering(disabled: true) }
        apply()
    }

    // MARK: Per-screen warmth and brightness

    /// A screen's own values, or the shared ones it hasn't been given its own yet.
    func look(_ key: String) -> (k: Double, b: Double) {
        (looks[key]?["k"] ?? d.double(forKey: "kelvin"), looks[key]?["b"] ?? d.double(forKey: "brightness"))
    }

    private func store(_ field: String, _ v: Double) {
        if selected == "all" {
            d.set(v, forKey: field == "k" ? "kelvin" : "brightness")
            for s in screens { looks[s.key, default: [:]][field] = v }
        } else {
            looks[selected, default: [:]][field] = v
        }
        d.set(looks, forKey: "screens")
    }

    private func load() {
        let l = look(selected == "all" ? screens.first?.key ?? "builtin" : selected)
        loading = true
        kelvin = l.k
        brightness = l.b
        loading = false
    }

    func refreshScreens() {
        let now = Display.screens()
        if now != screens { screens = now }
        if selected != "all", !now.contains(where: { $0.key == selected }) || now.count < 2 { selected = "all" }
    }

    private var builtinB: Double { look("builtin").b }

    private var inNight: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return startHour <= endHour ? (h >= startHour && h < endHour) : (h >= startHour || h < endHour)
    }

    // Per display: warmth and total brightness. On the built-in screen dim = backlight x gamma; elsewhere gamma only.
    typealias Look = (k: Double, dim: Double)
    private var shown: [CGDirectDisplayID: Look] = [:]
    private func shownLook(_ id: CGDirectDisplayID) -> Look { shown[id] ?? (6500, CGDisplayIsBuiltin(id) != 0 ? lastHW ?? 1 : 1) }
    private lazy var lastHW: Double? = Display.builtin.flatMap(Backlight.get).map(Double.init)
    private var wasActive = false
    private var anim: Timer?
    private let minBacklight = 1.0 / 16 // dimmest brightness-key step; below it Dusk dims in software

    func apply() {
        let active = enabled && (!scheduleOn || inNight)
        // Brightness keys or auto-brightness moved the backlight: follow the change instead of fighting it.
        if anim == nil, let id = Display.builtin, let last = lastHW, let b = Backlight.get(id).map(Double.init), abs(b - last) > 0.02 {
            lastHW = b
            let next = min(max(builtinB + b - last, 0.05), 1)
            if abs(next - builtinB) > 0.001 {
                if selected == "builtin" || (selected == "all" && screens.first?.builtin == true) { brightness = next; return } // didSet re-applies
                looks["builtin", default: [:]]["b"] = next
                d.set(looks, forKey: "screens")
            }
        }
        let animate = active != wasActive || anim != nil
        wasActive = active
        anim?.invalidate(); anim = nil
        let pin = flickerFree && active
        var target: [CGDirectDisplayID: Look] = [:]
        for id in Display.activeDisplays() {
            let builtin = CGDisplayIsBuiltin(id) != 0
            let l = look(Display.key(id))
            target[id] = active ? (l.k, l.b) : (6500, builtin ? max(builtinB, minBacklight) : 1)
        }

        let finish = { [self] in
            gammaOK = render(target, pin: pin)
            shown = target
            if !active { Display.resetGamma() }
        }
        guard animate else { return finish() }

        // Sunset on, sunrise off: ease warmth (in mireds, so it looks even) and brightness with the curtain.
        let from = shown, start = Date(), dur = SweepView.duration
        anim = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            let x = min(Date().timeIntervalSince(start) / dur, 1)
            if x >= 1 { t.invalidate(); self.anim = nil; return finish() }
            let e = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
            var now: [CGDirectDisplayID: Look] = [:]
            for (id, to) in target {
                let a = from[id] ?? self.shownLook(id)
                let m = 1e6 / a.k + (1e6 / to.k - 1e6 / a.k) * e
                now[id] = (1e6 / m, a.dim + (to.dim - a.dim) * e)
            }
            self.shown = now
            _ = self.render(now, pin: pin)
        }
    }

    /// Splits the built-in screen's brightness between backlight and gamma. Flicker-free holds the backlight
    /// at 100% and does it all in gamma; otherwise the backlight does the work down to its lowest step.
    private func render(_ looks: [CGDirectDisplayID: Look], pin: Bool) -> Bool {
        var ok = true
        for (id, l) in looks {
            guard CGDisplayIsBuiltin(id) != 0 else { ok = Display.setGamma(id, kelvin: l.k, dim: l.dim) && ok; continue }
            var hw = pin ? 1 : max(l.dim, minBacklight)
            let up = hw > (lastHW ?? hw)
            if !up { setBacklight(id, hw) } // going darker: backlight first, so it never flashes brighter
            var g = Display.setGamma(id, kelvin: l.k, dim: l.dim / hw)
            if pin && !g { // gamma didn't take: holding 100% would make the screen brighter
                hw = max(l.dim, minBacklight)
                g = Display.setGamma(id, kelvin: l.k, dim: l.dim / hw)
            }
            setBacklight(id, hw)
            ok = ok && g
        }
        return ok
    }

    private func setBacklight(_ id: CGDirectDisplayID, _ v: Double) {
        if let l = lastHW, abs(l - v) < 0.002, let now = Backlight.get(id), abs(Double(now) - v) < 0.01 { return }
        Backlight.set(id, Float(v))
        lastHW = v
    }

    // MARK: Self-test for the settings page

    enum Health { case ok, warn, off }
    struct Check: Identifiable { let id: String; let state: Health; let text: String }
    @Published var checks: [Check] = []

    func runChecks() {
        apply() // re-pin and re-apply first, so the result shows the real current state
        if antiDither { Display.setDithering(disabled: true) }
        checks = [flickerCheck(), ditherCheck()]
    }

    private func flickerCheck() -> Check {
        let pct = { (v: Double) in "\(Int((v * 100).rounded()))%" }
        func c(_ s: Health, _ t: String) -> Check { Check(id: "flicker", state: s, text: t) }
        guard flickerFree else { return c(.off, "Flicker-free is off. At low brightness the backlight dims by pulsing on and off very fast (PWM), which some eyes feel.") }
        guard enabled && (!scheduleOn || inNight) else { return c(.off, "Dusk is paused right now, so the backlight is back in your hands.") }
        guard let id = Display.builtin else { return c(.warn, "No built-in screen found. Flicker-free works on MacBook screens only.") }
        if Display.builtinIsMiniLED {
            return c(.warn, "This Mac has a mini-LED (XDR) screen. Its backlight pulses about 15,000 times a second at every brightness, even 100%, so flicker-free can't remove it here and only uses extra battery. You can turn it off.")
        }
        guard gammaOK else { return c(.warn, "macOS didn't accept the colour change, so Dusk left the backlight alone to keep the screen from getting brighter.") }
        guard let b = Backlight.get(id) else { return c(.warn, "Couldn't read the backlight on this Mac.") }
        guard b >= 0.99 else { return c(.warn, "Backlight is at \(pct(Double(b))), not 100%. Turn off \"Automatically adjust brightness\" in System Settings > Displays.") }
        return c(.ok, "Working. The backlight is held at 100%, so it doesn't pulse, and Dusk dims the picture to \(pct(builtinB)) instead.")
    }

    private func ditherCheck() -> Check {
        func c(_ s: Health, _ t: String) -> Check { Check(id: "dither", state: s, text: t) }
        guard let states = Display.ditherStates() else { return c(.warn, "Not available on this Mac. It needs Apple silicon (M1 or later).") }
        guard antiDither else { return c(.off, "No dithering is off. The screen adds faint moving noise to fake extra shades, which can look like shimmer.") }
        let on = states.filter { $0 }.count
        if on == 0 { return c(.ok, "Working. Dithering is off, so pixels hold still.") }
        return c(.warn, "Dithering is still on for some screens. macOS can turn it back on; switch No dithering off and on again.")
    }

    func shutdown() {
        anim?.invalidate()
        if let id = Display.builtin { Backlight.set(id, Float(max(wasActive ? builtinB : shownLook(id).dim, minBacklight))) }
        Display.resetGamma()
    }
}
