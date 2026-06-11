# `ColorHex.swift`

> Two-way conversion between hex strings (`#RRGGBB[AA]`) and Apple's color types, with graceful fallbacks so a bad string never makes a color disappear.

**Location:** `Sources/Jerusalem/Support/ColorHex.swift`
**Role:** pure-logic namespace (implemented as type extensions)

## What it does (plain English)

Colors are stored in the database as hex strings like `#3B82F6` (and sometimes with alpha, `#3B82F6CC`), because a string is easy to persist and human-readable. But the renderer and the editor need real color *objects*. This file adds the glue: it teaches `NSColor` (AppKit's color) and `Color` (SwiftUI's color) how to be built *from* a hex string and how to produce a hex string *from* themselves.

It does this with **extensions** — Swift's way of adding methods to an existing type you don't own, similar to monkey-patching a prototype in JS but type-safe and scoped. So everywhere else in the code you can just write `NSColor(hex: "#FF0000")` or `someColor.hexString`.

The defensive design matters: the string-to-color initializers are *failable* (they return `null` on garbage input) so callers can fall back — which is exactly why the renderer writes `NSColor(hex: ...) ?? .black`. The SwiftUI `Color(hex:)` even bakes the fallback in (white), so the editor never ends up showing an invisible color.

## Swift you'll meet in this file

| Swift | JS/TS meaning |
| --- | --- |
| `extension NSColor { ... }` | Add members to an existing type (like extending a prototype, but scoped/typed) |
| `convenience init?(hex: String)` | A failable constructor — returns `null` (the whole init) on bad input |
| `var s = hex.trimming...` | A mutable local (`let` in JS); `let` would be `const` |
| `guard let value = UInt64(s, radix: 16) else { return nil }` | Parse hex to an unsigned int; bail to `null` if it isn't valid hex |
| `(value >> 16) & 0xFF` | Bit-shift and mask — same operators as JS |
| `switch s.count { case 6: ...; case 8: ...; default: return nil }` | Branch on string length |
| `self.init(srgbRed:green:blue:alpha:)` | Call the real constructor with the parsed channels |
| `var hexString: String { ... }` | A computed property (a getter), like a TS `get hexString()` |
| `String(format: "#%02X%02X%02X", ...)` | `printf`-style formatting — two-digit uppercase hex per channel |
| `usingColorSpace(.sRGB) ?? self` | Convert to sRGB; if that returns null, keep the original |

## Code walkthrough

### `NSColor(hex:)` — string to color

```swift
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
```

It trims whitespace, strips a leading `#`, and parses the rest as base-16. If parsing fails, the whole initializer returns `nil` (the `?` on `init?`). It then splits the integer into channels: 6 digits means RGB with full opacity; 8 digits means RGBA; any other length is invalid and returns `nil`. Each channel is divided by 255 to get the `0.0...1.0` range AppKit wants, in the sRGB color space.

### `NSColor.hexString` — color to string

```swift
var hexString: String {
    let converted = usingColorSpace(.sRGB) ?? self
    let r = Int((converted.redComponent * 255).rounded())
    let g = Int((converted.greenComponent * 255).rounded())
    let b = Int((converted.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
}
```

It first normalizes to sRGB (some colors live in other color spaces and would give nonsense channel values otherwise), reads each channel back as `0...255`, clamps to be safe, and formats as `#RRGGBB`. Note: alpha is intentionally dropped on the way out — this getter produces the 6-digit form.

### SwiftUI `Color` bridge

```swift
extension Color {
    init(hex string: String) {
        self = Color(nsColor: NSColor(hex: string) ?? .white)
    }

    var hexString: String {
        NSColor(self).hexString
    }
}
```

These reuse the `NSColor` logic so there's one source of truth. The SwiftUI `Color(hex:)` is *not* failable — it falls back to white if the hex is bad, so an editor `ColorPicker` always gets a visible color. `Color.hexString` round-trips through `NSColor` because SwiftUI's dynamic colors don't directly expose concrete channel values; bouncing through `NSColor` resolves them to a real sRGB triple.

## How it connects

- **Used pervasively by the renderer.** `SlideRenderer` calls `NSColor(hex:)` for every background, fill, stroke, shadow, and text color, always with a fallback (`?? .black`, `?? .white`, `?? .systemBlue`).
- **Used by the editor.** The Phase 8 editor uses `hexString` to persist `ColorPicker` selections back into the SwiftData model, and `Color(hex:)` to load them — that's the round-trip noted in the doc comments.
- **No dependencies** beyond AppKit/SwiftUI; it's pure string↔color math, easy to reason about and test.

## Gotchas / why it matters

- **Failable in, fallback out.** `NSColor(hex:)` returns `nil` for bad input *on purpose* — that's what lets the renderer never crash on a malformed color and always paint *something*. Don't "fix" it to force a default; the caller's `??` is doing deliberate work.
- **6 vs 8 digits.** Only those two lengths are valid. A 3-digit shorthand (`#FFF`) is **not** supported — it returns `nil`.
- **Alpha is lost on export.** `hexString` always emits `#RRGGBB`. If you need to persist transparency, that's a gap to be aware of.
- **sRGB normalization.** Always converting to sRGB before reading channels avoids garbage values from colors defined in other spaces — keep that step if you touch `hexString`.
