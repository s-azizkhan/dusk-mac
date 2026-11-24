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
    private var savedBacklight: Float?
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
    @Published var kelvin: Double { didSet { d.set(kelvin, forKey: "kelvin"); apply() } }
    @Published var brightness: Double { didSet { d.set(brightness, forKey: "brightness"); apply() } }
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
        // First run with flicker-free: start the software dim at the current backlight so the screen doesn't jump brighter.
        if d.object(forKey: "brightness") == nil, d.object(forKey: "flickerFree") as? Bool ?? true,
           let id = Display.builtin, let b = Backlight.get(id) {
            d.set(max(Double(b), 0.05), forKey: "brightness")
        }
        d.register(defaults: ["enabled": true, "kelvin": 3400.0, "brightness": 1.0, "startHour": 20, "endHour": 7,
                              "flickerFree": true, "antiDither": true])
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

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.apply() }
        CGDisplayRegisterReconfigurationCallback({ _, _, ctx in
            guard let ctx else { return }
            DispatchQueue.main.async { Unmanaged<Controller>.fromOpaque(ctx).takeUnretainedValue().apply() }
        }, Unmanaged.passUnretained(self).toOpaque())
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.apply() }
        if antiDither { Display.setDithering(disabled: true) }
        apply()
    }

    private var inNight: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return startHour <= endHour ? (h >= startHour && h < endHour) : (h >= startHour || h < endHour)
    }

    private var shown = (k: 6500.0, dim: 1.0) // what the gamma table shows right now
    private var wasActive = false
    private var anim: Timer?

    func apply() {
        let active = enabled && (!scheduleOn || inNight)
        let animate = active != wasActive || anim != nil
        wasActive = active
        anim?.invalidate(); anim = nil
        let id = Display.builtin
        let pin = flickerFree && active
        // Flicker-free: hand the backlight's level over to gamma first, so pinning to 100% looks the same.
        if pin, let id, savedBacklight == nil, let b = Backlight.get(id),
           Display.applyGamma(kelvin: shown.k, dim: shown.dim * Double(b)) {
            savedBacklight = b
            Backlight.set(id, 1)
            shown.dim *= Double(b)
        }
        let unpin = !pin && savedBacklight != nil
        let target = active ? (k: kelvin, dim: brightness) : (k: 6500.0, dim: unpin ? Double(savedBacklight!) : 1)

        let finish = { [self] in
            gammaOK = Display.applyGamma(kelvin: target.k, dim: target.dim)
            shown = target
            // Unpin, or gamma didn't take: give the backlight back, else the screen would be brighter.
            if let id, let s = savedBacklight, unpin || !gammaOK {
                Backlight.set(id, s)
                savedBacklight = nil
                if active { gammaOK = Display.applyGamma(kelvin: target.k, dim: target.dim) }
                else { Display.resetGamma(); shown = (6500, 1) }
            }
        }
        guard animate else { return finish() }

        // Sunset on, sunrise off: ease warmth (in mireds, so it looks even) and dim with the curtain.
        let from = shown, start = Date(), dur = SweepView.duration
        anim = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            let x = min(Date().timeIntervalSince(start) / dur, 1)
            if x >= 1 { t.invalidate(); self.anim = nil; return finish() }
            let e = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
            let m = 1e6 / from.k + (1e6 / target.k - 1e6 / from.k) * e
            self.shown = (1e6 / m, from.dim + (target.dim - from.dim) * e)
            _ = Display.applyGamma(kelvin: self.shown.k, dim: self.shown.dim)
        }
    }

    func shutdown() {
        anim?.invalidate()
        if let id = Display.builtin, let s = savedBacklight { Backlight.set(id, s) }
        Display.resetGamma()
    }
}
