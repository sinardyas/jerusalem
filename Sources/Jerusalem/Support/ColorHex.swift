import AppKit

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
}
