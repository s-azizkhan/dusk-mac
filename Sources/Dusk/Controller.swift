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

    /// Master switch. Each screen also has its own on/off (`power` while that screen is picked).
    @Published var enabled: Bool {
        didSet {
            d.set(enabled, forKey: "enabled")
            apply()
            sweep(on: enabled, ids: Set(screens.filter { on($0.key) }.map(\.id)))
        }
    }
    @Published var sweepStart: Date?
    @Published var sweepOn = true

    private func sweep(on: Bool, ids: Set<CGDirectDisplayID>) {
        let start = Date()
        sweepOn = on
        sweepStart = start
        ScreenSweep.play(on: on, only: ids)
        DispatchQueue.main.asyncAfter(deadline: .now() + SweepView.duration) { [weak self] in
            if self?.sweepStart == start { self?.sweepStart = nil }
        }
    }

    func on(_ key: String) -> Bool { (looks[key]?["on"] ?? 1) > 0.5 }

    private func setOn(_ key: String, _ v: Bool) { looks[key, default: [:]]["on"] = v ? 1 : 0 }

    /// On/off for what the picker shows: one screen, or all of them.
    var power: Bool {
        get { selected == "all" ? enabled && (screens.isEmpty || screens.contains { on($0.key) }) : enabled && on(selected) }
        set {
            objectWillChange.send()
            if selected == "all" {
                if newValue { screens.forEach { setOn($0.key, true) } }
                d.set(looks, forKey: "screens")
                if enabled != newValue { enabled = newValue } else { apply(); sweep(on: newValue, ids: Set(screens.map(\.id))) }
                return
            }
            let id = screens.first { $0.key == selected }.map { Set([$0.id]) } ?? []
            if newValue && !enabled { screens.forEach { setOn($0.key, $0.key == selected) } } // master was off: turn on just this one
            setOn(selected, newValue)
            d.set(looks, forKey: "screens")
            if newValue && !enabled { enabled = true; return }
            if !newValue && !screens.contains(where: { on($0.key) }) { enabled = false; return }
            apply()
            sweep(on: newValue, ids: id)
        }
    }
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
    private var wasActive: [CGDirectDisplayID: Bool] = [:]
    private var anim: Timer?
    private let minBacklight = 1.0 / 16 // dimmest brightness-key step; below it Dusk dims in software

    func apply() {
        let live = enabled && (!scheduleOn || inNight)
        let isActive = { (id: CGDirectDisplayID) in live && self.on(Display.key(id)) }
        let active = Display.activeDisplays().contains(where: isActive)
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
        let now = Dictionary(uniqueKeysWithValues: Display.activeDisplays().map { ($0, isActive($0)) })
        let animate = now.contains { wasActive[$0.key] != $0.value } || anim != nil
        wasActive = now
        anim?.invalidate(); anim = nil
        let pin = flickerFree && !Display.builtinIsMiniLED && Display.builtin.map(isActive) == true // mini-LED pulses at 100% too
        var target: [CGDirectDisplayID: Look] = [:]
        for id in Display.activeDisplays() {
            let builtin = CGDisplayIsBuiltin(id) != 0
            let l = look(Display.key(id))
            // ponytail: a screen that's off while others stay on gets a plain ramp, not its ColorSync profile
            target[id] = isActive(id) ? (l.k, l.b * ddcScale(Display.key(id))) : (6500, builtin ? max(builtinB, minBacklight) : 1)
        }

        let finish = { [self] in
            gammaOK = render(target, pin: pin)
            shown = target
            if !active { Display.resetGamma() }
            syncDDC(live: isActive)
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

    // MARK: Flicker-free on external monitors (DDC)

    enum DDCState: Equatable { case unsupported, held }
    @Published private(set) var ddc: [String: DDCState] = [:]
    private var ddcBusy: Set<String> = []
    private let ddcQ = DispatchQueue(label: "dusk.ddc")

    /// While the monitor is held at full brightness, gamma also carries the level it was at, so nothing jumps.
    private func ddcScale(_ key: String) -> Double {
        guard ddc[key] == .held, let s = looks[key]?["ddcScale"] else { return 1 }
        return s
    }

    /// Holds each active external monitor at 100% over DDC when flicker-free is on; gives it back otherwise.
    /// DDC is slow (~0.1 s), so it runs off the main thread and only when the wanted state changes.
    private func syncDDC(live: (CGDirectDisplayID) -> Bool) {
        for s in screens where !s.builtin && !ddcBusy.contains(s.key) {
            let want = flickerFree && live(s.id)
            let held = ddc[s.key] == .held
            guard want != held, !(want && ddc[s.key] == .unsupported) else { continue }
            ddcBusy.insert(s.key)
            let key = s.key, id = s.id, saved = looks[key]?["ddc0"]
            ddcQ.async { [weak self] in
                var state: DDCState? = nil
                var orig: Double? = nil, scale: Double? = nil
                if let av = DDC.service(for: id), let b = DDC.brightness(av) {
                    if want {
                        let o = saved ?? Double(b.cur) // a saved value means Dusk already raised it (crash or quit)
                        if DDC.setBrightness(av, b.max) { state = .held; orig = o; scale = max(o / Double(b.max), 0.05) }
                    } else if let o = saved {
                        DDC.setBrightness(av, Int(o))
                    }
                } else if want { state = .unsupported }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.ddcBusy.remove(key)
                    self.ddc[key] = state
                    if let orig, let scale { self.looks[key, default: [:]]["ddc0"] = orig; self.looks[key]?["ddcScale"] = scale }
                    if state == nil { self.looks[key]?["ddc0"] = nil; self.looks[key]?["ddcScale"] = nil }
                    self.d.set(self.looks, forKey: "screens")
                    self.apply()
                }
            }
        }
    }

    // MARK: Self-test for the settings page

    enum Health { case ok, warn, off }
    struct Check: Identifiable { let id: String; let state: Health; let text: String }
    @Published var checks: [Check] = []

    func runChecks() {
        apply() // re-pin and re-apply first, so the result shows the real current state
        if antiDither { Display.setDithering(disabled: true) }
        ddc = ddc.filter { $0.value != .unsupported } // probe again on test
        apply()
        checks = [flickerCheck()] + screens.filter { !$0.builtin }.map(externalCheck) + [ditherCheck()]
    }

    private func flickerCheck() -> Check {
        let pct = { (v: Double) in "\(Int((v * 100).rounded()))%" }
        func c(_ s: Health, _ t: String) -> Check { Check(id: "flicker", state: s, text: t) }
        guard flickerFree else { return c(.off, "Flicker-free is off. At low brightness the backlight dims by pulsing on and off very fast (PWM), which some eyes feel.") }
        guard enabled && (!scheduleOn || inNight) && on("builtin") else { return c(.off, "Dusk is off for this screen right now, so the backlight is back in your hands.") }
        guard let id = Display.builtin else { return c(.warn, "No built-in screen found. Flicker-free works on MacBook screens only.") }
        if Display.builtinIsMiniLED {
            return c(.warn, "This Mac has a mini-LED (XDR) screen. Its backlight pulses about 15,000 times a second at every brightness, even 100%, so flicker-free can't remove it here and only uses extra battery. You can turn it off.")
        }
        guard gammaOK else { return c(.warn, "macOS didn't accept the colour change, so Dusk left the backlight alone to keep the screen from getting brighter.") }
        guard let b = Backlight.get(id) else { return c(.warn, "Couldn't read the backlight on this Mac.") }
        guard b >= 0.99 else { return c(.warn, "Backlight is at \(pct(Double(b))), not 100%. Turn off \"Automatically adjust brightness\" in System Settings > Displays.") }
        return c(.ok, "Working. The backlight is held at 100%, so it doesn't pulse, and Dusk dims the picture to \(pct(builtinB)) instead.")
    }

    private func externalCheck(_ s: Display.Screen) -> Check {
        func c(_ st: Health, _ t: String) -> Check { Check(id: "ext-\(s.key)", state: st, text: "\(s.name): \(t)") }
        guard flickerFree else { return c(.off, "flicker-free is off.") }
        guard on(s.key), enabled else { return c(.off, "Dusk is off for this screen.") }
        if screens.filter({ !$0.builtin }).count > 1 { return c(.warn, "flicker-free works on one external screen at a time for now.") }
        switch ddc[s.key] {
        case .held: return c(.ok, "the monitor is held at full brightness over DDC, and Dusk dims the picture instead.")
        case .unsupported: return c(.warn, "the monitor didn't answer over DDC. On M1 Pro and Max MacBook Pros the HDMI port doesn't pass DDC: use USB-C or DisplayPort, and turn on DDC/CI in the monitor's menu. Or set the monitor to 100% yourself and dim it here.")
        case nil: return c(.warn, "checking the monitor over DDC. Press Test again in a moment.")
        }
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
        for s in screens where ddc[s.key] == .held {
            if let av = DDC.service(for: s.id), let o = looks[s.key]?["ddc0"] { DDC.setBrightness(av, Int(o)) }
            looks[s.key]?["ddc0"] = nil; looks[s.key]?["ddcScale"] = nil
        }
        d.set(looks, forKey: "screens")
        if let id = Display.builtin { Backlight.set(id, Float(max(wasActive[id] == true ? builtinB : shownLook(id).dim, minBacklight))) }
        Display.resetGamma()
    }
}
