# `SlideElement.swift`

> A single positioned thing on a slide — styled text, an image, or a vector shape — with its frame stored in resolution-independent normalized coordinates.

**Location:** `Sources/Jerusalem/Models/SlideElement.swift`
**Role:** SwiftData model + three enums (`SlideElementKind`, `TextAlignmentOption`, `ShapeType`)

## What it does (plain English)
A `SlideElement` is one drawable layer on a `Slide`. There are three kinds — `text`, `image`, and `shape` — and they all share this one model; you just set the fields relevant to the kind (text uses `text`/`fontName`/…, image uses `imageFilename`, shape uses `shapeType`/`fillColorHex`/…).

The crucial design choice is the **frame** (`x`, `y`, `width`, `height`): it's stored as fractions from `0` to `1` relative to the slide, not as pixels. So `x = 0.08, width = 0.84` means "start 8% from the left, span 84% of the width" — which renders identically whether the output is 1280×720 or a 4K projector. Likewise `fontSize` is in points at a fixed 1920×1080 reference, so it scales proportionally. This is what lets one slide look right on any screen.

Most of the file is text styling (font, color, alignment, bold/italic/underline, shadow, stroke, auto-fit, line/letter spacing) plus a smaller set of shape fields. Many fields were added in later phases with defaults chosen to keep existing slides looking exactly the same.

## Swift you'll meet in this file
- `enum X: String, Codable, Hashable, Sendable { case … }` — string-backed enums ≈ `type X = "a" | "b"`. `Codable` = JSON-serializable; `Hashable` = Map/Set-key-able; `Sendable` = safe across concurrency.
- `@Model final class` — SwiftData entity; `final` = no `extends`.
- `Double` / `Bool` / `String?` — `number` / `boolean` / `string | null`.
- `private var …Raw: String` + computed enum accessor — the enum-storage convention (appears three times here): a private backing string + `get/set`.
- Optionals + `??` — `String?` is `string | null`; `text ?? ""` is nil-coalescing (`?? ""`).
- `switch` returning values per case; nested `switch` ≈ `switch`/`return` or a `Record` lookup.
- String helpers: `.trimmingCharacters(in:)` ≈ `.trim()`, `.isEmpty` ≈ `=== ""`, `String(trimmed.prefix(32))` ≈ `trimmed.slice(0, 32)`.
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

**TypeScript equivalent**

```ts
type SlideElementKind = "text" | "image" | "shape";
type TextAlignmentOption = "leading" | "center" | "trailing" | "justified";
type ShapeType = "rectangle" | "ellipse" | "roundedRectangle";
```

**Swift syntax:**
- `enum Foo: String, … { case a, b }` — a string-backed enum (each case's `rawValue` is its name); the protocols make it JSON-codable, Map/Set-key-able, and concurrency-safe. TS: a string-literal union.

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

**TypeScript equivalent**

```ts
// @Entity
class SlideElement {
  order: number = 0;
  private kindRaw: string = "text"; // SlideElementKind.text.rawValue

  // Normalized frame relative to the slide (0...1, top-left origin)
  x: number = 0.08;
  y: number = 0.55;
  width: number = 0.84;
  height: number = 0.32;
}
```

**Swift syntax:**
- `var x: Double = 0.08` — a mutable `number` property with a default. `Double` is double-precision floating point.

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

**TypeScript equivalent**

```ts
  text: string | null = null;
  fontName: string = "Avenir Next";
  fontSize: number = 48;              // points at the 1920×1080 reference
  colorHex: string = "#FFFFFF";
  private alignmentRaw: string = "center"; // TextAlignmentOption.center.rawValue
  isBold: boolean = true;
  isItalic: boolean = false;
  isUnderlined: boolean = false;
  hasShadow: boolean = true;
  hasStroke: boolean = false;
  autoFit: boolean = true;
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

**TypeScript equivalent**

```ts
  lineSpacingMultiplier: number = 1.35;
  letterSpacing: number = 0;
  strokeWidth: number = 3.0;
  strokeColorHex: string = "#000000";
  shadowBlur: number = 12;
  shadowOffsetY: number = -4;
  shadowColorHex: string = "#000000B3"; // #RRGGBBAA — black at ~70% opacity
```

Deeper typography added later. The comment notes the defaults were chosen to **preserve the original visuals exactly**, so old slides don't visually shift when the app loads them with the new fields. (`#000000B3` is a hex color with an alpha byte — black at ~70% opacity.)

```swift
    var imageFilename: String?
```

**TypeScript equivalent**

```ts
  imageFilename: string | null = null;  // set for image elements; file under MediaStorage
```

Set for image elements; names a file under `MediaStorage`.

```swift
    private var shapeTypeRaw: String = ShapeType.rectangle.rawValue
    var fillColorHex: String = "#3B82F6"
    var cornerRadius: Double = 0
```

**TypeScript equivalent**

```ts
  private shapeTypeRaw: string = "rectangle"; // ShapeType.rectangle.rawValue
  fillColorHex: string = "#3B82F6";
  cornerRadius: number = 0; // points at 1920×1080 reference; only for roundedRectangle
```

Shape fields. A shape is a vector primitive filled with `fillColorHex`, optionally bordered by reusing the same `hasStroke`/`strokeWidth`/`strokeColorHex` fields as text. `cornerRadius` is in points at the 1920×1080 reference (like `fontSize`) and only matters for `.roundedRectangle`.

```swift
    var slide: Slide?
```

**TypeScript equivalent**

```ts
  slide: Slide | null = null;  // back-link, inverse of Slide.elements
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

**TypeScript equivalent**

```ts
constructor(kind: SlideElementKind, order: number = 0, text: string | null = null) {
  this.kindRaw = kind;   // kind.rawValue
  this.order = order;
  this.text = text;
}
```

**Swift syntax:**
- `order: Int = 0`, `text: String? = nil` — **default parameters**; only `kind` is required. Called `SlideElement(kind: .text)`.

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

**TypeScript equivalent**

```ts
get kind(): SlideElementKind {
  const cases: SlideElementKind[] = ["text", "image", "shape"];
  return cases.includes(this.kindRaw as SlideElementKind)
    ? (this.kindRaw as SlideElementKind) : "text"; // ?? .text
}
set kind(v: SlideElementKind) { this.kindRaw = v; }

get alignment(): TextAlignmentOption {
  const cases: TextAlignmentOption[] = ["leading", "center", "trailing", "justified"];
  return cases.includes(this.alignmentRaw as TextAlignmentOption)
    ? (this.alignmentRaw as TextAlignmentOption) : "center"; // ?? .center
}
set alignment(v: TextAlignmentOption) { this.alignmentRaw = v; }

get shapeType(): ShapeType {
  const cases: ShapeType[] = ["rectangle", "ellipse", "roundedRectangle"];
  return cases.includes(this.shapeTypeRaw as ShapeType)
    ? (this.shapeTypeRaw as ShapeType) : "rectangle"; // ?? .rectangle
}
set shapeType(v: ShapeType) { this.shapeTypeRaw = v; }
```

**Swift syntax:**
- Same trio as elsewhere: `Enum(rawValue:)` failable init → optional, `?? .fallback` nil-coalesce, `newValue.rawValue` written back in the setter. The `private …Raw: String` is the real persisted column; the computed property is the typed face.

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

**TypeScript equivalent**

```ts
get layerName(): string {
  switch (this.kind) {
    case "text": {
      const trimmed = (this.text ?? "").trim();
      return trimmed === "" ? "Text" : trimmed.slice(0, 32);
    }
    case "image":
      return this.imageFilename ?? "Image";
    case "shape":
      switch (this.shapeType) {
        case "rectangle":        return "Rectangle";
        case "ellipse":          return "Ellipse";
        case "roundedRectangle": return "Rounded Rectangle";
      }
  }
}
```

**Swift syntax:**
- `switch kind { case .text: … }` — exhaustive switch over an enum; the compiler errors if any case is unhandled (no `default` needed when all are covered). Nested `switch` works the same.
- `(text ?? "")` — nil-coalesce a `String?` to a non-optional `String`. TS: `text ?? ""`.
- `.trimmingCharacters(in: .whitespacesAndNewlines)` — trims a given character set. TS: `.trim()`.
- `cond ? a : b` — ternary, identical to TS.
- `String(trimmed.prefix(32))` — `prefix(32)` takes up to the first 32 elements (a `Substring`), wrapped back into a `String`. TS: `.slice(0, 32)`.
- `imageFilename ?? "Image"` — nil-coalesce. TS: `?? "Image"`.

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
