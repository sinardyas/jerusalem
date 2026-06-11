# `Slide.swift`

> One projected page belonging to an `Item` — its background plus the ordered visual elements drawn on top.

**Location:** `Sources/Jerusalem/Models/Slide.swift`
**Role:** SwiftData model + a `SlideBackgroundKind` enum

## What it does (plain English)
A `Slide` is a single page that gets projected on the audience screen. Each one belongs to exactly one `Item` (a song, sermon, Bible passage, …) and holds two things: a **background** (a flat color, a gradient, a still image, or a looping video) and an **ordered list of `SlideElement`s** (the text, images, and shapes painted on top).

For songs/text/Bible items, slides are normally *derived* — `ContentRebuilder` generates them from the item's authored content. But once a user opens a slide in the visual editor and changes it, the slide sets `isManuallyEdited = true`, which tells the rebuilder to leave it alone. That's the mechanism that lets hand-tweaked slides survive a re-split of the lyrics or sermon body.

## Swift you'll meet in this file
- `enum SlideBackgroundKind: String, Codable, Hashable, Sendable, CaseIterable` — a TS-union-style enum stored as a string. `Codable` = JSON-serializable; `Hashable` = usable as a Map/Set key; `Sendable` = safe to pass across concurrency boundaries; `CaseIterable` = loopable via `.allCases`.
- `@Model final class` — SwiftData entity; `final` = not subclassable.
- `String?` — optional, i.e. `string | null`.
- `Bool` / `Double` — boolean / floating-point.
- `private var backgroundKindRaw` + computed `backgroundKind` — the enum-storage convention (below).
- `@Relationship(deleteRule: .cascade, inverse: \SlideElement.slide)` — foreign-key relationship; cascade-deletes children; `inverse:` names the back-pointer.
- Computed property with a sorted copy — `var orderedElements: [SlideElement] { ... }`.

## Code walkthrough

### The background-kind enum
```swift
enum SlideBackgroundKind: String, Codable, Hashable, Sendable, CaseIterable {
    case color, gradient, image, video
}
```

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

- `order` is the slide's position within its item (used by `Item.orderedSlides`).
- `sectionLabel` is the operator-facing tag like `"Verse 1"` — optional, since continuation slides have none.
- `backgroundKindRaw` is the stored string behind the `backgroundKind` enum (see convention below).
- `backgroundColorHex` is the flat color (default a dark navy `#0F172A`). The two `…Filename` optionals point at files under `MediaStorage` when the background is an image or video.

```swift
    var gradientHex2: String?
    var gradientAngle: Double = 135
```

For gradient backgrounds: the **second** color stop (the first reuses `backgroundColorHex`) and an angle in degrees (`0` = left→right, `90` = top→bottom; default `135`). These are only consulted when `backgroundKind == .gradient`.

```swift
    var isManuallyEdited: Bool = false
```

The "don't regenerate me" flag. Once the user edits this slide in the WYSIWYG editor, this flips to `true` and `ContentRebuilder` refuses to overwrite it.

```swift
    @Relationship(deleteRule: .cascade, inverse: \SlideElement.slide)
    var elements: [SlideElement] = []

    var item: Item?
```

`elements` is the owned list of things drawn on the slide; `.cascade` means deleting the slide deletes its elements. `inverse: \SlideElement.slide` points to the `slide` back-reference on the element (the `\Type.property` is a *key path* — a type-safe reference to a property). `item` is the back-link to the owning `Item` (inverse of `Item.slides`).

### Constructor
```swift
init(order: Int, sectionLabel: String? = nil, backgroundColorHex: String = "#0F172A") {
    self.order = order
    self.sectionLabel = sectionLabel
    self.backgroundColorHex = backgroundColorHex
}
```

Only `order` is required; `sectionLabel` and `backgroundColorHex` have defaults (the `= nil` / `= "#0F172A"` work like JS default params).

### The enum-storage convention (`…Raw` + computed accessor)
```swift
var backgroundKind: SlideBackgroundKind {
    get { SlideBackgroundKind(rawValue: backgroundKindRaw) ?? .color }
    set { backgroundKindRaw = newValue.rawValue }
}
```

SwiftData stores the enum as a plain `String` column (`backgroundKindRaw`, marked `private`). The public `backgroundKind` getter rebuilds the enum from that string — `SlideBackgroundKind(rawValue:)` returns an optional, and `?? .color` (nullish coalescing) falls back to `.color` if the stored string is unrecognized. The setter writes `newValue.rawValue` back. `newValue` is the implicit setter argument, like the value handed to a JS setter.

### Ordered elements
```swift
var orderedElements: [SlideElement] {
    elements.sorted { $0.order < $1.order }
}
```

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
