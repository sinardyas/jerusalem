import AppKit
import SwiftUI

extension NSColor {
    /// Creates a color from a `#RRGGBB` or `#RRGGBBAA` hex string. Returns `nil`
    /// for malformed input so callers can fall back gracefully.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt64(s, radix: 16) else { return nil }

        let r, g, b, a: UInt64
        switch s.count {
        case 6:
            r = (value >> 16) & 0xFF; g = (value >> 8) & 0xFF; b = value & 0xFF; a = 0xFF
        case 8:
            r = (value >> 24) & 0xFF; g = (value >> 16) & 0xFF; b = (value >> 8) & 0xFF; a = value & 0xFF
        default:
            return nil
        }
        self.init(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                  blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    /// `#RRGGBB` representation of this color in sRGB. Used by the Phase 8 editor
    /// to persist `ColorPicker` selections back into the SwiftData model.
    var hexString: String {
        let converted = usingColorSpace(.sRGB) ?? self
        let r = Int((converted.redComponent * 255).rounded())
        let g = Int((converted.greenComponent * 255).rounded())
        let b = Int((converted.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}

extension Color {
    /// SwiftUI `Color` from a `#RRGGBB[AA]` string, with white fallback so the
    /// editor never gets stuck with an invisible color when the persisted hex
    /// is malformed.
    init(hex string: String) {
        self = Color(nsColor: NSColor(hex: string) ?? .white)
    }

    /// `#RRGGBB` representation — round-trips through `NSColor` so the SwiftUI
    /// dynamic-color types resolve to a concrete sRGB triple.
    var hexString: String {
        NSColor(self).hexString
    }
}
