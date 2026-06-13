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
| `extension NSColor { ... }` | Add members to an existing type — like patching a prototype, but scoped and type-safe |
| `convenience init?(hex: String)` | A **failable** constructor: the whole init returns `null` on bad input. Shape `init?` = "may return null" |
| `var s = hex.trimming...` | A mutable local (`let s = ...` in JS); Swift `let` would be `const` |
| `guard let value = UInt64(s, radix: 16) else { return nil }` | Parse hex → unsigned int; bail to `null` if it isn't valid hex |
| `(value >> 16) & 0xFF` | Bit-shift + mask — same operators as JS |
| `switch s.count { case 6: ...; case 8: ...; default: return nil }` | Branch on string length; `default` ≈ the `else`/`default` arm |
| `self.init(srgbRed:green:blue:alpha:)` | Delegate to the real constructor with the parsed channels |
| `var hexString: String { ... }` | A **computed property** (getter), like `get hexString()` in TS |
| `String(format: "#%02X%02X%02X", ...)` | `printf`-style formatting — two-digit uppercase hex per channel |
| `usingColorSpace(.sRGB) ?? self` | Convert to sRGB; if that returns null, keep `self` (the original) |

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

**TypeScript equivalent**

```ts
// A "failable constructor" — model it as a factory returning NSColor | null.
function NSColorFromHex(hex: string): NSColor | null {
  let s = hex.trim();
  if (s.startsWith("#")) s = s.slice(1);

  const value = parseHex(s);            // UInt64(s, radix: 16)
  if (value == null) return null;       // guard ... else return nil

  let r: number, g: number, b: number, a: number;
  switch (s.length) {
    case 6:
      r = (value >> 16) & 0xff; g = (value >> 8) & 0xff; b = value & 0xff; a = 0xff;
      break;
    case 8:
      r = (value >> 24) & 0xff; g = (value >> 16) & 0xff;
      b = (value >> 8) & 0xff;  a = value & 0xff;
      break;
    default:
      return null;
  }
  return new NSColor({ srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a / 255 });
}
```

It trims whitespace, strips a leading `#`, and parses the rest as base-16. If parsing fails, the whole initializer returns `nil` (the `?` on `init?`). It then splits the integer into channels: 6 digits means RGB with full opacity; 8 digits means RGBA; any other length is invalid and returns `nil`. Each channel is divided by 255 to get the `0.0...1.0` range AppKit wants, in the sRGB color space.

**Swift syntax:**
- `extension NSColor { ... }` — reopens a type you don't own to add members; everywhere else can then call `NSColor(hex:)`. Like patching a prototype, but scoped to where the extension is visible and fully type-checked.
- `convenience init?(hex:)` — a **failable initializer**: the trailing `?` means it can `return nil`, so its result type is effectively `NSColor?`. `convenience` means it delegates to a primary `self.init(...)` rather than setting every stored field itself.
- `var s = ...` — a mutable local (`let` in JS); needed because `s` is reassigned (`removeFirst()`).
- `guard let value = UInt64(s, radix: 16) else { return nil }` — try to parse; if it fails, bail out, otherwise `value` is the unwrapped non-optional int for the rest of the scope.
- `let r, g, b, a: UInt64` — declare four constants of one type up front, assigned later inside the `switch` (definite-assignment, like declaring `let` then assigning once per branch).

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

**TypeScript equivalent**

```ts
// A computed getter on NSColor.
get hexString(): string {
  const converted = this.usingColorSpace("sRGB") ?? this;
  const r = Math.round(converted.redComponent * 255);
  const g = Math.round(converted.greenComponent * 255);
  const b = Math.round(converted.blueComponent * 255);
  const clamp = (n: number) => Math.max(0, Math.min(255, n));
  const hex2 = (n: number) => clamp(n).toString(16).padStart(2, "0").toUpperCase();
  return `#${hex2(r)}${hex2(g)}${hex2(b)}`; // String(format: "#%02X%02X%02X", ...)
}
```

It first normalizes to sRGB (some colors live in other color spaces and would give nonsense channel values otherwise), reads each channel back as `0...255`, clamps to be safe, and formats as `#RRGGBB`. Note: alpha is intentionally dropped on the way out — this getter produces the 6-digit form.

**Swift syntax:**
- `var hexString: String { ... }` — a **computed property** (no stored value; runs the block on each access), exactly a TS `get hexString()`.
- `usingColorSpace(.sRGB) ?? self` — `??` falls back to the original color if conversion returns `nil`.
- `String(format: "#%02X%02X%02X", ...)` — C-style format string: `%02X` = two-digit, zero-padded, uppercase hex.

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

**TypeScript equivalent**

```ts
// Reuse the NSColor logic so there's one source of truth.
function ColorFromHex(hex: string): Color {
  // NOT failable: fall back to white so the editor never shows an invisible color
  return Color.fromNSColor(NSColorFromHex(hex) ?? NSColor.white);
}

// get hexString(): round-trip through NSColor to resolve a concrete sRGB triple
function colorHexString(color: Color): string {
  return new NSColor(color).hexString;
}
```

These reuse the `NSColor` logic so there's one source of truth. The SwiftUI `Color(hex:)` is *not* failable — it falls back to white if the hex is bad, so an editor `ColorPicker` always gets a visible color. `Color.hexString` round-trips through `NSColor` because SwiftUI's dynamic colors don't directly expose concrete channel values; bouncing through `NSColor` resolves them to a real sRGB triple.

**Swift syntax:**
- `init(hex string: String)` — `hex` is the external label, `string` is the internal name. Callers write `Color(hex: "...")` but the body uses `string`. This is a non-failable `init` (no `?`), so it always produces a `Color`.
- `self = Color(...)` — in a value-type initializer you can assign the whole instance to `self`.

## How it connects

- **Used pervasively by the renderer.** `SlideRenderer` calls `NSColor(hex:)` for every background, fill, stroke, shadow, and text color, always with a fallback (`?? .black`, `?? .white`, `?? .systemBlue`).
- **Used by the editor.** The Phase 8 editor uses `hexString` to persist `ColorPicker` selections back into the SwiftData model, and `Color(hex:)` to load them — that's the round-trip noted in the doc comments.
- **No dependencies** beyond AppKit/SwiftUI; it's pure string↔color math, easy to reason about and test.

## Gotchas / why it matters

- **Failable in, fallback out.** `NSColor(hex:)` returns `nil` for bad input *on purpose* — that's what lets the renderer never crash on a malformed color and always paint *something*. Don't "fix" it to force a default; the caller's `??` is doing deliberate work.
- **6 vs 8 digits.** Only those two lengths are valid. A 3-digit shorthand (`#FFF`) is **not** supported — it returns `nil`.
- **Alpha is lost on export.** `hexString` always emits `#RRGGBB`. If you need to persist transparency, that's a gap to be aware of.
- **sRGB normalization.** Always converting to sRGB before reading channels avoids garbage values from colors defined in other spaces — keep that step if you touch `hexString`.
