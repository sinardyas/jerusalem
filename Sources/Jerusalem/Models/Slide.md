# `Slide.swift`

> One projected page belonging to an `Item` — its background plus the ordered visual elements drawn on top.

**Location:** `Sources/Jerusalem/Models/Slide.swift`
**Role:** SwiftData model + a `SlideBackgroundKind` enum

## What it does (plain English)
A `Slide` is a single page that gets projected on the audience screen. Each one belongs to exactly one `Item` (a song, sermon, Bible passage, …) and holds two things: a **background** (a flat color, a gradient, a still image, or a looping video) and an **ordered list of `SlideElement`s** (the text, images, and shapes painted on top).

For songs/text/Bible items, slides are normally *derived* — `ContentRebuilder` generates them from the item's authored content. But once a user opens a slide in the visual editor and changes it, the slide sets `isManuallyEdited = true`, which tells the rebuilder to leave it alone. That's the mechanism that lets hand-tweaked slides survive a re-split of the lyrics or sermon body.

## Swift you'll meet in this file
- `enum SlideBackgroundKind: String, Codable, Hashable, Sendable, CaseIterable { case color, … }` — a string-backed enum ≈ `type SlideBackgroundKind = "color" | "gradient" | …`. `Codable` = JSON-serializable; `Hashable` = usable as a Map/Set key; `Sendable` = safe to pass across concurrency boundaries; `CaseIterable` = `.allCases`.
- `@Model final class` — SwiftData entity; `final` = no `extends`.
- `String?` — optional, i.e. `string | null`.
- `Bool` / `Double` — `boolean` / `number` (floating-point).
- `private var backgroundKindRaw` + computed `backgroundKind` — the enum-storage convention (below). TS: private backing string + `get/set`.
- `@Relationship(deleteRule: .cascade, inverse: \SlideElement.slide)` — relationship; cascade-deletes children; `inverse:` names the back-pointer; `\SlideElement.slide` is a **key path**.
- Computed property with a sorted copy — `var orderedElements: [SlideElement] { ... }` = `get orderedElements(): SlideElement[]`.

## Code walkthrough

### The background-kind enum
```swift
enum SlideBackgroundKind: String, Codable, Hashable, Sendable, CaseIterable {
    case color, gradient, image, video
}
```

**TypeScript equivalent**

```ts
type SlideBackgroundKind = "color" | "gradient" | "image" | "video";

// CaseIterable analog:
const SlideBackgroundKind = {
  allCases: ["color", "gradient", "image", "video"] as SlideBackgroundKind[],
};
```

**Swift syntax:**
- `enum Foo: String, Codable, Hashable, Sendable, CaseIterable { case … }` — a string-backed enum conforming to several protocols (interfaces): JSON-serializable, usable as a dictionary/set key, concurrency-safe, and `.allCases`-loopable. TS: a string-literal union (`Hashable`/`Sendable` have no TS equivalent — string unions are already comparable and immutable).

Four explicit background modes. The comment explains *why* it's explicit: earlier code inferred the background from "which `…Filename` happens to be set," which is ambiguous. Making it a real enum lets the inspector switch cleanly between color / gradient / image / video without guessing intent.

### The model and its fields
```swift
@Model
final class Slide {
    var order: Int = 0
    var sectionLabel: String?            // e.g. "Verse 1", "Chorus"
    private var backgroundKindRaw: String = SlideBackgroundKind.color.rawValue
    var backgroundColorHex: String = "#0F172A"
    var backgroundImageFilename: String? // optional static image background
    var backgroundVideoFilename: String? // optional looping motion background
```

**TypeScript equivalent**

```ts
// @Entity
class Slide {
  order: number = 0;
  sectionLabel: string | null = null;          // e.g. "Verse 1", "Chorus"
  private backgroundKindRaw: string = "color";  // SlideBackgroundKind.color.rawValue
  backgroundColorHex: string = "#0F172A";
  backgroundImageFilename: string | null = null; // optional static image background
  backgroundVideoFilename: string | null = null; // optional looping motion background
}
```

**Swift syntax:**
- `var sectionLabel: String?` — optional (`string | null`); continuation slides have none.
- `private var backgroundKindRaw` — the `private` raw string backing the enum, hidden from callers.

- `order` is the slide's position within its item (used by `Item.orderedSlides`).
- `sectionLabel` is the operator-facing tag like `"Verse 1"` — optional, since continuation slides have none.
- `backgroundKindRaw` is the stored string behind the `backgroundKind` enum (see convention below).
- `backgroundColorHex` is the flat color (default a dark navy `#0F172A`). The two `…Filename` optionals point at files under `MediaStorage` when the background is an image or video.

```swift
    var gradientHex2: String?
    var gradientAngle: Double = 135
```

**TypeScript equivalent**

```ts
  gradientHex2: string | null = null;  // second color stop (first reuses backgroundColorHex)
  gradientAngle: number = 135;         // degrees: 0 = left→right, 90 = top→bottom
```

For gradient backgrounds: the **second** color stop (the first reuses `backgroundColorHex`) and an angle in degrees (`0` = left→right, `90` = top→bottom; default `135`). These are only consulted when `backgroundKind == .gradient`.

```swift
    var isManuallyEdited: Bool = false
```

**TypeScript equivalent**

```ts
  isManuallyEdited: boolean = false;  // once true, ContentRebuilder won't overwrite this slide
```

The "don't regenerate me" flag. Once the user edits this slide in the WYSIWYG editor, this flips to `true` and `ContentRebuilder` refuses to overwrite it.

```swift
    @Relationship(deleteRule: .cascade, inverse: \SlideElement.slide)
    var elements: [SlideElement] = []

    var item: Item?
```

**TypeScript equivalent**

```ts
  // @OneToMany(cascade) inverse: SlideElement.slide
  elements: SlideElement[] = [];

  item: Item | null = null;  // back-link, inverse of Item.slides
```

**Swift syntax:**
- `@Relationship(deleteRule: .cascade, inverse: \SlideElement.slide)` — cascade-deletes the elements with the slide; `inverse:` names the back-pointer; `\SlideElement.slide` is a **key path** (type-safe field reference).

`elements` is the owned list of things drawn on the slide; `.cascade` means deleting the slide deletes its elements. `inverse: \SlideElement.slide` points to the `slide` back-reference on the element (the `\Type.property` is a *key path* — a type-safe reference to a property). `item` is the back-link to the owning `Item` (inverse of `Item.slides`).

### Constructor
```swift
init(order: Int, sectionLabel: String? = nil, backgroundColorHex: String = "#0F172A") {
    self.order = order
    self.sectionLabel = sectionLabel
    self.backgroundColorHex = backgroundColorHex
}
```

**TypeScript equivalent**

```ts
constructor(
  order: number,
  sectionLabel: string | null = null,
  backgroundColorHex: string = "#0F172A",
) {
  this.order = order;
  this.sectionLabel = sectionLabel;
  this.backgroundColorHex = backgroundColorHex;
}
```

**Swift syntax:**
- `sectionLabel: String? = nil` / `backgroundColorHex: String = "#0F172A"` — **default parameters**; only `order` is required. Called `Slide(order: 0)`.

Only `order` is required; `sectionLabel` and `backgroundColorHex` have defaults (the `= nil` / `= "#0F172A"` work like JS default params).

### The enum-storage convention (`…Raw` + computed accessor)
```swift
var backgroundKind: SlideBackgroundKind {
    get { SlideBackgroundKind(rawValue: backgroundKindRaw) ?? .color }
    set { backgroundKindRaw = newValue.rawValue }
}
```

**TypeScript equivalent**

```ts
get backgroundKind(): SlideBackgroundKind {
  const cases: SlideBackgroundKind[] = ["color", "gradient", "image", "video"];
  return cases.includes(this.backgroundKindRaw as SlideBackgroundKind)
    ? (this.backgroundKindRaw as SlideBackgroundKind)
    : "color"; // ?? .color
}
set backgroundKind(newValue: SlideBackgroundKind) {
  this.backgroundKindRaw = newValue; // newValue.rawValue
}
```

**Swift syntax:**
- `var x: Enum { get { … } set { … } }` — computed property with getter and setter.
- `Enum(rawValue: s)` — failable initializer; returns an optional (`nil` if no case matches).
- `?? .color` — nil-coalescing fallback. TS: `?? "color"`.
- `newValue` — implicit setter argument.

SwiftData stores the enum as a plain `String` column (`backgroundKindRaw`, marked `private`). The public `backgroundKind` getter rebuilds the enum from that string — `SlideBackgroundKind(rawValue:)` returns an optional, and `?? .color` (nullish coalescing) falls back to `.color` if the stored string is unrecognized. The setter writes `newValue.rawValue` back. `newValue` is the implicit setter argument, like the value handed to a JS setter.

### Ordered elements
```swift
var orderedElements: [SlideElement] {
    elements.sorted { $0.order < $1.order }
}
```

**TypeScript equivalent**

```ts
get orderedElements(): SlideElement[] {
  return [...this.elements].sort((a, b) => a.order - b.order);
}
```

**Swift syntax:**
- `.sorted { $0.order < $1.order }` — new sorted array via a trailing closure; `$0`/`$1` are the two compared elements. TS: `[...arr].sort((a, b) => a.order - b.order)`.

Returns the elements sorted by `order`, which is also **draw order, back to front** — element 0 is painted first (furthest back), later ones on top. `$0`/`$1` are the two elements being compared, like `(a, b) => a.order < b.order`.

## How it connects
- Belongs to one `Item` (via `item`, the inverse of `Item.slides`).
- Owns many `SlideElement`s (via `elements`); each element points back through `SlideElement.slide`.
- The renderer reads a *snapshot* of this model — not the live `@Model` object — to draw the audience output (see the project's edit/live separation invariant).

## Gotchas / why it matters
- **`isManuallyEdited` is load-bearing.** It's the only thing protecting hand-edited slides from being clobbered when content is re-derived. Set it whenever the editor mutates a slide.
- **`order` is both sequence and z-order.** For slides it's presentation order; for the slide's `elements` the same field is back-to-front draw order. Always read `orderedElements`/`orderedSlides`, never the raw sets.
- **Background fields are mode-dependent.** `gradientHex2`/`gradientAngle` only matter for `.gradient`; the `…Filename` fields only for `.image`/`.video`. The `backgroundKind` enum is the single source of truth for which set applies.
- **Hex colors are strings.** Colors are stored as hex strings (`"#0F172A"`), parsed elsewhere into actual color objects.
