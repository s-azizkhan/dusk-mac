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

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled"); apply() } }
    @Published var kelvin: Double { didSet { d.set(kelvin, forKey: "kelvin"); apply() } }
    @Published var brightness: Double { didSet { d.set(brightness, forKey: "brightness"); apply() } }
    @Published var flickerFree: Bool { didSet { d.set(flickerFree, forKey: "flickerFree"); apply() } }
    @Published var antiDither: Bool { didSet { d.set(antiDither, forKey: "antiDither"); Display.setDithering(disabled: antiDither) } }
    @Published var scheduleOn: Bool { didSet { d.set(scheduleOn, forKey: "scheduleOn"); apply() } }
    @Published var startHour: Int { didSet { d.set(startHour, forKey: "startHour"); apply() } }
    @Published var endHour: Int { didSet { d.set(endHour, forKey: "endHour"); apply() } }
    @Published var gammaOK = true
    @Published var launchAtLogin: Bool {
        didSet { try? (launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()) }
    }

    init() {
        d.register(defaults: ["enabled": true, "kelvin": 3400.0, "brightness": 1.0, "startHour": 20, "endHour": 7])
        enabled = d.bool(forKey: "enabled")
        kelvin = d.double(forKey: "kelvin")
        brightness = d.double(forKey: "brightness")
        flickerFree = d.bool(forKey: "flickerFree")
        antiDither = d.bool(forKey: "antiDither")
        scheduleOn = d.bool(forKey: "scheduleOn")
        startHour = d.integer(forKey: "startHour")
        endHour = d.integer(forKey: "endHour")
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

    func apply() {
        let active = enabled && (!scheduleOn || inNight)
        let k = active ? kelvin : 6500
        let dim = active ? brightness : 1
        gammaOK = Display.applyGamma(kelvin: k, dim: dim)
        // Pin backlight only if gamma verifiably applied, else pinning would brighten the screen.
        guard let id = Display.builtin else { return }
        if flickerFree && active && gammaOK {
            if savedBacklight == nil { savedBacklight = Backlight.get(id) }
            Backlight.set(id, 1)
        } else if let s = savedBacklight {
            Backlight.set(id, s)
            savedBacklight = nil
        }
    }

    func shutdown() {
        if let id = Display.builtin, let s = savedBacklight { Backlight.set(id, s) }
        Display.resetGamma()
    }
}
