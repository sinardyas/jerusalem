# `Theme.swift`

> A reusable bundle of default visual styling (background color, font, text styling) that can be applied to slides.

**Location:** `Sources/Jerusalem/Models/Theme.swift`
**Role:** SwiftData model

## What it does (plain English)
A `Theme` is a saved "look" — a default background color, font, size, text color, and a full set of text-styling toggles (bold, shadow, stroke, spacing, etc.). The MVP ships a single `"Default Dark"` theme; a richer theme library comes later.

Practically, a theme is the *seed* of styling for new slides. When a slide/element is created, the theme's values become its starting style. The styling fields here deliberately mirror the fields on `SlideElement`, and their defaults are chosen to match what the existing `Theme.apply(to:)` logic already produces — so existing themes stay visually identical until the user changes them. An `Item` can optionally point at one `Theme` (see `Item.theme`).

## Swift you'll meet in this file
- `@Model final class` — SwiftData entity (like a Prisma model); `final` = not subclassable.
- `UUID` / `UUID()` — unique-id type and generator.
- `String` / `Double` / `Bool` — string, float, boolean.
- `private`-free stored properties with defaults — plain columns.
- `private var alignmentRaw` paired with a computed `alignment` — the enum-storage convention (here the raw field happens to be declared without `private`, but it's the same pattern).
- Computed property `var alignment: TextAlignmentOption { get/set }` — a getter+setter that maps a string column to a typed enum.
- `init(... = "...")` — default parameter.

## Code walkthrough

### The model and base styling
```swift
@Model
final class Theme {
    var uuid: UUID = UUID()
    var name: String = "Default Dark"
    var backgroundColorHex: String = "#0F172A"
    var fontName: String = "Avenir Next"
    var fontSize: Double = 48
    var textColorHex: String = "#FFFFFF"
```

`uuid` is a stable external id. `name` is the display name. The rest are the core look: a dark navy background (`#0F172A`), Avenir Next at 48 points (the same 1920×1080-reference scale used elsewhere), white text. Colors are hex strings, parsed into real colors elsewhere.

### Captured element styling
```swift
    var alignmentRaw: String = "center"
    var isBold: Bool = true
    var isItalic: Bool = false
    var isUnderlined: Bool = false
    var hasShadow: Bool = true
    var hasStroke: Bool = false
    var autoFit: Bool = true
    var lineSpacingMultiplier: Double = 1.35
    var letterSpacing: Double = 0
    var strokeWidth: Double = 3.0
    var strokeColorHex: String = "#000000"
    var shadowBlur: Double = 12
    var shadowOffsetY: Double = -4
    var shadowColorHex: String = "#000000B3"
```

This block is a near-exact copy of the styling fields on `SlideElement`. The comment explains they're captured from a "Set as default style for new slides" action, and the defaults match what `Theme.apply(to:)` already does — so adding these columns doesn't change how existing themes render. (`#000000B3` is black with an alpha byte ≈ 70% opacity.) `alignmentRaw` is the stored string behind the `alignment` enum.

### Constructor
```swift
init(name: String = "Default Dark") {
    self.name = name
}
```

Just takes an optional `name` (defaulting to `"Default Dark"`); every other field uses its property default.

### The enum-storage convention
```swift
var alignment: TextAlignmentOption {
    get { TextAlignmentOption(rawValue: alignmentRaw) ?? .center }
    set { alignmentRaw = newValue.rawValue }
}
```

Same pattern seen across the models: a `String` column (`alignmentRaw`) is the real storage, and a computed `alignment` property exposes it as the typed `TextAlignmentOption` enum (defined in `SlideElement.swift`). The getter rebuilds the enum from the string, falling back to `.center` if it's unrecognized (`?? .center`); the setter writes `newValue.rawValue` back. `newValue` is the implicit setter argument, like the value passed to a JS setter.

## How it connects
- `TextAlignmentOption` is shared with `SlideElement` (defined there).
- An `Item` optionally references a `Theme` (`Item.theme`); it's a one-way, non-cascading link, so deleting an item doesn't delete the theme and vice versa.
- The styling fields intentionally parallel `SlideElement`'s, so `Theme.apply(to:)` (elsewhere) can copy them straight onto new elements.

## Gotchas / why it matters
- **Defaults are a visual contract.** They reproduce the pre-existing look; changing a default would silently restyle existing themes/slides on next load.
- **Theme is a seed, not a live binding.** Applying a theme copies values onto slides/elements; later editing a theme doesn't retroactively change slides already created from it (unless explicitly re-applied).
- **Colors are hex strings.** Stored as `"#RRGGBB"` (or `"#RRGGBBAA"` with alpha), parsed into color objects elsewhere.
