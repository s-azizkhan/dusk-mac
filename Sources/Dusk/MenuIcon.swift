import AppKit

enum MenuIcon {
    /// Brand mark: sun with horizontal slits in its lower half. Template, so macOS tints it.
    static func make(on: Bool, size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width / 18
            let disc = NSBezierPath(ovalIn: NSRect(x: 1.5 * s, y: 1.5 * s, width: 15 * s, height: 15 * s))
            NSGraphicsContext.saveGraphicsState()
            let cut = NSBezierPath(rect: rect)
            cut.windingRule = .evenOdd
            for (y, h) in [(7.4, 1.1), (4.9, 1.5), (2.4, 1.9)] {
                cut.append(NSBezierPath(rect: NSRect(x: 0, y: y * s, width: rect.width, height: h * s)))
            }
            cut.addClip()
            NSColor.black.setFill()
            NSColor.black.setStroke()
            if on {
                disc.fill()
            } else {
                disc.lineWidth = 1.5 * s
                disc.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        img.isTemplate = true
        return img
    }
}
