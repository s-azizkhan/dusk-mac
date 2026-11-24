import AppKit
import CoreGraphics
import Foundation
import IOKit

enum Display {
    static var builtin: CGDirectDisplayID? {
        activeDisplays().first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids
    }

    // Tanner Helland approximation, extended below 1000K toward deep red.
    static func rgb(kelvin: Double) -> (r: Double, g: Double, b: Double) {
        let t = max(kelvin, 1000) / 100
        var r = 1.0, g: Double, b: Double
        if t > 66 { r = 1.2929 * pow(t - 60, -0.1332) }
        g = t <= 66 ? 0.39008 * log(t) - 0.63184 : 1.12989 * pow(t - 60, -0.0755)
        if t >= 66 { b = 1 } else if t <= 19 { b = 0 } else { b = 0.54320 * log(t - 10) - 1.19625 }
        if kelvin < 1000 {
            let f = max((kelvin - 500) / 500, 0)
            g *= 0.4 + 0.6 * f
            b *= f
        }
        let c = { (v: Double) in min(max(v, 0), 1) }
        return (c(r), c(g), c(b))
    }

    /// Applies warmth + software dim to every display. Returns false if readback disagrees.
    @discardableResult
    static func applyGamma(kelvin: Double, dim all: Double, builtinDim: Double? = nil) -> Bool {
        let (r, g, b) = rgb(kelvin: kelvin)
        var ok = true
        for id in activeDisplays() {
            let dim = CGDisplayIsBuiltin(id) != 0 ? builtinDim ?? all : all
            CGSetDisplayTransferByFormula(id, 0, Float(r * dim), 1, 0, Float(g * dim), 1, 0, Float(b * dim), 1)
            var rMin: Float = 0, rMax: Float = 0, rGam: Float = 0
            var gMin: Float = 0, gMax: Float = 0, gGam: Float = 0
            var bMin: Float = 0, bMax: Float = 0, bGam: Float = 0
            CGGetDisplayTransferByFormula(id, &rMin, &rMax, &rGam, &gMin, &gMax, &gGam, &bMin, &bMax, &bGam)
            if abs(Double(rMax) - r * dim) > 0.02 { ok = false }
        }
        return ok
    }

    static func resetGamma() { CGDisplayRestoreColorSyncSettings() }

    // Temporal dithering off via IORegistry (same technique as Stillcolor). Resets on reboot.
    static func setDithering(disabled: Bool) {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferAP"), &it) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(it) }
        while case let svc = IOIteratorNext(it), svc != 0 {
            IORegistryEntrySetCFProperty(svc, "enableDither" as CFString, (disabled ? kCFBooleanFalse : kCFBooleanTrue))
            IOObjectRelease(svc)
        }
    }
}

extension Display {
    /// Mini-LED (Liquid Retina XDR) built-in screens report a high EDR headroom. Their backlight
    /// pulses (~15 kHz PWM) at every level, so holding it at 100% can't stop the flicker.
    static var builtinIsMiniLED: Bool {
        NSScreen.screens.contains { s in
            let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return id.map { CGDisplayIsBuiltin($0) != 0 } == true && s.maximumPotentialExtendedDynamicRangeColorComponentValue >= 8
        }
    }

    /// enableDither per framebuffer (true = dithering on). nil when the Mac has none (Intel).
    static func ditherStates() -> [Bool]? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferAP"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var out: [Bool] = []
        while case let svc = IOIteratorNext(it), svc != 0 {
            if let v = IORegistryEntryCreateCFProperty(svc, "enableDither" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool { out.append(v) }
            IOObjectRelease(svc)
        }
        return out.isEmpty ? nil : out
    }
}

// Built-in panel backlight via private DisplayServices (same as MonitorControl).
enum Backlight {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32
    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    static func get(_ id: CGDirectDisplayID) -> Float? {
        guard let lib, let s = dlsym(lib, "DisplayServicesGetBrightness") else { return nil }
        var v: Float = 0
        return unsafeBitCast(s, to: GetFn.self)(id, &v) == 0 ? v : nil
    }

    @discardableResult
    static func set(_ id: CGDirectDisplayID, _ value: Float) -> Bool {
        guard let lib, let s = dlsym(lib, "DisplayServicesSetBrightness") else { return false }
        return unsafeBitCast(s, to: SetFn.self)(id, value) == 0
    }
}
