import CoreText
import SwiftUI

enum Fonts {
    /// Registers bundled fonts for this process. Falls back to system fonts if missing.
    static func register(from dir: URL? = Bundle.main.resourceURL?.appendingPathComponent("Fonts")) {
        guard let dir, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    static func serif(_ size: CGFloat) -> Font { .custom("InstrumentSerif-Regular", size: size) }
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Geist", size: size).weight(weight) }
    static func geistMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Geist Mono", size: size).weight(weight) }
}
