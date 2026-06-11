# `SlideElement.swift`

> A single positioned thing on a slide — styled text, an image, or a vector shape — with its frame stored in resolution-independent normalized coordinates.

**Location:** `Sources/Jerusalem/Models/SlideElement.swift`
**Role:** SwiftData model + three enums (`SlideElementKind`, `TextAlignmentOption`, `ShapeType`)

## What it does (plain English)
A `SlideElement` is one drawable layer on a `Slide`. There are three kinds — `text`, `image`, and `shape` — and they all share this one model; you just set the fields relevant to the kind (text uses `text`/`fontName`/…, image uses `imageFilename`, shape uses `shapeType`/`fillColorHex`/…).

The crucial design choice is the **frame** (`x`, `y`, `width`, `height`): it's stored as fractions from `0` to `1` relative to the slide, not as pixels. So `x = 0.08, width = 0.84` means "start 8% from the left, span 84% of the width" — which renders identically whether the output is 1280×720 or a 4K projector. Likewise `fontSize` is in points at a fixed 1920×1080 reference, so it scales proportionally. This is what lets one slide look right on any screen.

Most of the file is text styling (font, color, alignment, bold/italic/underline, shadow, stroke, auto-fit, line/letter spacing) plus a smaller set of shape fields. Many fields were added in later phases with defaults chosen to keep existing slides looking exactly the same.

## Swift you'll meet in this file
- `enum X: String, Codable, Hashable, Sendable` — string-backed enums; `Codable` = JSON-serializable, `Hashable` = Map/Set-key-able, `Sendable` = safe across concurrency.
- `@Model final class` — SwiftData entity; `final` = not subclassable.
- `Double` / `Bool` / `String?` — float / boolean / nullable string.
- `private var …Raw: String` + computed enum accessor — the enum-storage convention (appears three times here).
- Optionals + `??` — `String?` is `string | null`; `text ?? ""` is nullish coalescing.
- `switch` returning values per case; nested `switch`.
- String helpers: `.trimmingCharacters(in:)`, `.isEmpty`, `String(trimmed.prefix(32))` (take first 32 chars).
- `init(... = nil)` — default parameters.

## Code walkthrough

### The three enums
```swift
enum SlideElementKind: String, Codable, Hashable, Sendable { case text, image, shape }
enum TextAlignmentOption: String, Codable, Hashable, Sendable {
    case leading, center, trailing, justified
}
enum ShapeType: String, Codable, Hashable, Sendable {
    case rectangle, ellipse, roundedRectangle
}
```

`SlideElementKind` says what the element *is*. `TextAlignmentOption` is horizontal text alignment (`leading`/`trailing` are start/end-relative, friendlier than left/right for i18n). `ShapeType` lists the vector primitives the renderer can draw beneath images and text.

### The model: frame in normalized coordinates
```swift
@Model
final class SlideElement {
    var order: Int = 0
    private var kindRaw: String = SlideElementKind.text.rawValue

    var x: Double = 0.08
    var y: Double = 0.55
    var width: Double = 0.84
    var height: Double = 0.32
```

`order` is the back-to-front draw order within the slide. `kindRaw` is the stored string behind `kind`. The four frame fields are the normalized rectangle — all `0...1` relative to the slide, with a top-left origin. The defaults place a text box in the lower portion of the slide.

### Text content and styling
```swift
    var text: String?
    var fontName: String = "Avenir Next"
    var fontSize: Double = 48
    var colorHex: String = "#FFFFFF"
    private var alignmentRaw: String = TextAlignmentOption.center.rawValue
    var isBold: Bool = true
    var isItalic: Bool = false
    var isUnderlined: Bool = false
    var hasShadow: Bool = true
    var hasStroke: Bool = false
    var autoFit: Bool = true
```

`fontSize: 48` is points **at the 1920×1080 reference** — the renderer scales it to the real output size. `colorHex` is a hex string. `autoFit` lets text shrink to fit its frame. `alignmentRaw` is the stored string behind the `alignment` enum.

```swift
    var lineSpacingMultiplier: Double = 1.35
    var letterSpacing: Double = 0
    var strokeWidth: Double = 3.0
    var strokeColorHex: String = "#000000"
    var shadowBlur: Double = 12
    var shadowOffsetY: Double = -4
    var shadowColorHex: String = "#000000B3"
```

Deeper typography added later. The comment notes the defaults were chosen to **preserve the original visuals exactly**, so old slides don't visually shift when the app loads them with the new fields. (`#000000B3` is a hex color with an alpha byte — black at ~70% opacity.)

```swift
    var imageFilename: String?
```

Set for image elements; names a file under `MediaStorage`.

```swift
    private var shapeTypeRaw: String = ShapeType.rectangle.rawValue
    var fillColorHex: String = "#3B82F6"
    var cornerRadius: Double = 0
```

Shape fields. A shape is a vector primitive filled with `fillColorHex`, optionally bordered by reusing the same `hasStroke`/`strokeWidth`/`strokeColorHex` fields as text. `cornerRadius` is in points at the 1920×1080 reference (like `fontSize`) and only matters for `.roundedRectangle`.

```swift
    var slide: Slide?
```

Back-link to the owning slide — the inverse of `Slide.elements`.

### Constructor
```swift
init(kind: SlideElementKind, order: Int = 0, text: String? = nil) {
    self.kindRaw = kind.rawValue
    self.order = order
    self.text = text
}
```

Takes a typed `kind` but stores its `rawValue`. `order` and `text` have defaults.

### The enum-storage convention, three times
```swift
var kind: SlideElementKind {
    get { SlideElementKind(rawValue: kindRaw) ?? .text }
    set { kindRaw = newValue.rawValue }
}

var alignment: TextAlignmentOption {
    get { TextAlignmentOption(rawValue: alignmentRaw) ?? .center }
    set { alignmentRaw = newValue.rawValue }
}

var shapeType: ShapeType {
    get { ShapeType(rawValue: shapeTypeRaw) ?? .rectangle }
    set { shapeTypeRaw = newValue.rawValue }
}
```

Same pattern in triplicate: a `private …Raw: String` column is the real storage; the public computed property converts to/from the enum. The getter does `Enum(rawValue:) ?? .fallback` (nullish-coalesce to a safe default if the string is unrecognized); the setter writes `newValue.rawValue`. SwiftData persists the plain string; callers always work with the typed enum.

### `layerName` — a human label for the Layers panel
```swift
var layerName: String {
    switch kind {
    case .text:
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Text" : String(trimmed.prefix(32))
    case .image:
        return imageFilename ?? "Image"
    case .shape:
        switch shapeType {
        case .rectangle:        return "Rectangle"
        case .ellipse:          return "Ellipse"
        case .roundedRectangle: return "Rounded Rectangle"
        }
    }
}
```

A computed label shown in the editor's Layers panel:
- **Text:** `(text ?? "")` defaults nil to empty, `.trimmingCharacters(in: .whitespacesAndNewlines)` strips surrounding whitespace; if empty, label is `"Text"`, otherwise the first 32 characters (`String(trimmed.prefix(32))`).
- **Image:** the filename, or `"Image"` if none (`imageFilename ?? "Image"`).
- **Shape:** a nested `switch` on `shapeType` giving a friendly name.

## How it connects
- Belongs to one `Slide` via `slide` (inverse of `Slide.elements`).
- Drawn by `SlideRenderer`, which reads an immutable *snapshot* (`RenderableElement`), never this live `@Model` object — that's the edit/live separation invariant.
- Its normalized frame + reference-point `fontSize`/`cornerRadius` are what make slides resolution-independent.

## Gotchas / why it matters
- **Never store pixels.** Keep `x/y/width/height` in `0...1` and sizes in 1920×1080-reference points, or slides will break on different outputs.
- **Defaults are a compatibility contract.** The later-phase fields default to values that reproduce the original look; changing those defaults would silently shift every existing slide.
- **One model, many kinds.** Only the fields matching `kind` are meaningful; `kind` is the discriminator. Shapes deliberately reuse the text stroke fields.
- **Enum convention again:** follow the `private …Raw` + computed accessor pattern for any new enum field.
