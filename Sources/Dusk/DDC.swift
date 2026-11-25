import CoreGraphics
import Foundation
import IOKit

// External monitor brightness over DDC/CI on Apple silicon (IOAVService, same protocol as MonitorControl).
@_silgen_name("IOAVServiceCreateWithService") private func IOAVServiceCreateWithService(_ a: CFAllocator?, _ s: io_service_t) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOAVServiceReadI2C") private func IOAVServiceReadI2C(_ s: CFTypeRef, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn
@_silgen_name("IOAVServiceWriteI2C") private func IOAVServiceWriteI2C(_ s: CFTypeRef, _ chip: UInt32, _ addr: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn

enum DDC {
    private static let brightnessCode: UInt8 = 0x10

    /// The DDC service for an external display.
    /// ponytail: pairs only when there is exactly one external screen; EDID matching if people run several.
    static func service(for id: CGDirectDisplayID) -> CFTypeRef? {
        guard CGDisplayIsBuiltin(id) == 0 else { return nil }
        let externals = Display.activeDisplays().filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
        guard externals == [id] else { return nil }
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var found: [CFTypeRef] = []
        while case let svc = IOIteratorNext(it), svc != 0 {
            let loc = IORegistryEntryCreateCFProperty(svc, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            if loc == "External", let av = IOAVServiceCreateWithService(kCFAllocatorDefault, svc)?.takeRetainedValue() { found.append(av) }
            IOObjectRelease(svc)
        }
        return found.count == 1 ? found[0] : nil
    }

    /// Current and max brightness, or nil unless the monitor sends back a valid, checksummed VCP reply.
    static func brightness(_ av: CFTypeRef) -> (cur: Int, max: Int)? {
        for _ in 0..<4 {
            var q: [UInt8] = [0x82, 0x01, brightnessCode, 0x6E ^ 0x82 ^ 0x01 ^ brightnessCode]
            for _ in 0..<2 { usleep(10_000); _ = IOAVServiceWriteI2C(av, 0x37, 0x51, &q, 4) }
            usleep(50_000)
            var r = [UInt8](repeating: 0, count: 11)
            guard IOAVServiceReadI2C(av, 0x37, 0, &r, 11) == kIOReturnSuccess else { continue }
            let chk = r[0..<10].reduce(UInt8(0x50)) { $0 ^ $1 }
            // 6E 88 02 <result 00> <vcp> <type> maxHi maxLo curHi curLo chk
            if chk == r[10], r[1] == 0x88, r[2] == 0x02, r[3] == 0x00, r[4] == brightnessCode {
                let mx = Int(r[6]) << 8 | Int(r[7])
                if mx > 0 { return (Int(r[8]) << 8 | Int(r[9]), mx) }
            }
            usleep(20_000)
        }
        return nil
    }

    @discardableResult
    static func setBrightness(_ av: CFTypeRef, _ v: Int) -> Bool {
        var p: [UInt8] = [0x84, 0x03, brightnessCode, UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF), 0]
        p[5] = p[0..<5].reduce(UInt8(0x6E ^ 0x51)) { $0 ^ $1 }
        var ok = false
        for _ in 0..<2 { usleep(10_000); ok = IOAVServiceWriteI2C(av, 0x37, 0x51, &p, 6) == kIOReturnSuccess || ok }
        return ok
    }
}
