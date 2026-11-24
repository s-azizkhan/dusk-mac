import AppKit
import CoreGraphics

// Usage: swift tools/make-icon.swift  -> Resources/Dusk.icns, docs/icon.png
let cs = CGColorSpaceCreateDeviceRGB()
func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, a])!
}
func grad(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}

func render(px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: body, cornerWidth: 188, cornerHeight: 188, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: col(0x000000, 0.45))
    ctx.addPath(path); ctx.setFillColor(col(0x1B1446)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()

    // night background
    ctx.drawLinearGradient(grad([(0, col(0x0E0A2A)), (1, col(0x2A1D66))]),
                           start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])

    // warm halo behind the sun
    let c = CGPoint(x: 512, y: 470), r: CGFloat = 250
    ctx.drawRadialGradient(grad([(0, col(0xFF7A5C, 0.55)), (0.55, col(0xF2507B, 0.18)), (1, col(0xF2507B, 0))]),
                           startCenter: c, startRadius: r, endCenter: c, endRadius: 470, options: [])

    // slit sun: circle minus horizontal bands in its lower half
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)); ctx.clip()
    let cut = CGMutablePath()
    cut.addRect(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    for (y, h) in [(430.0, 16.0), (372.0, 24.0), (308.0, 32.0), (236.0, 42.0)] {
        cut.addRect(CGRect(x: 0, y: y, width: 1024, height: h))
    }
    ctx.addPath(cut); ctx.clip(using: .evenOdd)
    ctx.drawLinearGradient(grad([(0, col(0xF2507B)), (0.45, col(0xFF9A4D)), (1, col(0xFFE08A))]),
                           start: CGPoint(x: 0, y: c.y - r), end: CGPoint(x: 0, y: c.y + r), options: [])
    ctx.restoreGState()

    // top sheen
    ctx.drawLinearGradient(grad([(0, col(0xFFFFFF, 0.10)), (1, col(0xFFFFFF, 0))]),
                           start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 700), options: [])
    ctx.restoreGState()

    // edge
    ctx.addPath(path); ctx.setStrokeColor(col(0xFFFFFF, 0.12)); ctx.setLineWidth(3); ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = "build/Dusk.iconset"
try? fm.removeItem(atPath: set)
try fm.createDirectory(atPath: set, withIntermediateDirectories: true)
try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try fm.createDirectory(atPath: "docs", withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(px: base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try render(px: base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
try render(px: 512).write(to: URL(fileURLWithPath: "docs/icon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set, "-o", "Resources/Dusk.icns"]
try p.run(); p.waitUntilExit()
print("icon status", p.terminationStatus)
