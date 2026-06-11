# `SongSection.swift`

> A block of raw lyrics (a verse, chorus, bridge, or tag) belonging to a song — the authored source of truth that slides are derived from.

**Location:** `Sources/Jerusalem/Models/SongSection.swift`
**Role:** SwiftData model + a `SongSectionKind` enum

## What it does (plain English)
For a song `Item`, the *authored* content isn't the slides — it's a list of `SongSection`s. Each section is one labeled block of lyrics: "Verse 1", "Chorus", "Bridge", a "Tag". The raw, original multi-line lyrics are stored verbatim in `lyrics`.

The slides you actually project are **derived** from these sections by `ContentRebuilder`. Keeping the original text intact (rather than only storing the chopped-up slides) is what lets the operator change the "lines per slide" setting and have everything re-flow correctly — the source lyrics and their line breaks are never lost. So: edit sections → rebuilder regenerates slides.

## Swift you'll meet in this file
- `enum SongSectionKind: String, Codable, CaseIterable, Identifiable, Sendable` — a string-backed enum. `Codable` = JSON-serializable; `CaseIterable` = loop via `.allCases`; `Identifiable` = has a stable `id` (for SwiftUI lists); `Sendable` = concurrency-safe.
- `@Model final class` — SwiftData entity; `final` = not subclassable.
- `Int?` / `String` — optional integer / string.
- `private var kindRaw: String` + computed `kind` — the enum-storage convention.
- `Item?` — optional back-reference.
- `if let number { ... }` — optional unwrap (shorthand, reuses the name).
- `init(... = nil, ... = 0, ... = "")` — default parameters.
- `\(...)` — string interpolation, like JS `${...}`.

## Code walkthrough

### The `SongSectionKind` enum
```swift
enum SongSectionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case verse, chorus, bridge, tag
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .verse:  "Verse"
        case .chorus: "Chorus"
        case .bridge: "Bridge"
        case .tag:    "Tag"
        }
    }
}
```

Four structural roles. `id` returns the `rawValue` so SwiftUI can identify each case in a list. `displayName` maps each case to a UI label via a value-returning `switch` (each case is an expression — no `return` keyword needed).

### The model
```swift
@Model
final class SongSection {
    var order: Int = 0
    private var kindRaw: String = SongSectionKind.verse.rawValue
    var number: Int?
    var lyrics: String = ""

    var item: Item?
```

- `order` is the section's position within the song (read via `Item.orderedSongSections`).
- `kindRaw` is the stored string behind the `kind` enum.
- `number` is an optional ordinal to disambiguate repeats — "Verse **2**". The comment notes that by convention only verses are numbered, but the model doesn't enforce that.
- `lyrics` is the raw, newline-separated text, stored verbatim.
- `item` is the back-reference to the owning song (inverse of `Item.songSections`).

### Constructor
```swift
init(kind: SongSectionKind, number: Int? = nil, order: Int = 0, lyrics: String = "") {
    self.kindRaw = kind.rawValue
    self.number = number
    self.order = order
    self.lyrics = lyrics
}
```

Only `kind` is required; the rest default (`nil`, `0`, `""`). As elsewhere, it takes a typed `kind` but stores its `rawValue`.

### The enum-storage convention
```swift
var kind: SongSectionKind {
    get { SongSectionKind(rawValue: kindRaw) ?? .verse }
    set { kindRaw = newValue.rawValue }
}
```

SwiftData persists the enum as a plain `String` (`kindRaw`, `private`); the public `kind` getter rebuilds the enum (`?? .verse` falls back if the string is unrecognized), and the setter writes the raw value back. `newValue` is the implicit setter argument.

### `displayLabel`
```swift
var displayLabel: String {
    if let number { return "\(kind.displayName) \(number)" }
    return kind.displayName
}
```

Builds the label shown on the **first** slide of this section in the grid — `"Verse 1"`, `"Chorus"`. `if let number { ... }` runs only when `number` is non-nil and includes it; otherwise just the kind's name. The comment notes continuation slides intentionally get no label. `"\(kind.displayName) \(number)"` is string interpolation, like `` `${kind.displayName} ${number}` ``.

## How it connects
- Belongs to one `Item` (a song) via `item`, the inverse of `Item.songSections`.
- `Item.orderedSongSections` sorts these by `order` — the source-of-truth view for the song.
- `ContentRebuilder` reads these (plus the item's `linesPerSlide`) and materializes the `Slide`/`SlideElement` rows that actually get projected. This model never renders directly.

## Gotchas / why it matters
- **Sections are the source of truth, slides are derived.** Edit sections; the rebuilder regenerates slides. Don't treat the generated slides as canonical for songs (unless a slide is flagged `isManuallyEdited`).
- **`lyrics` is stored verbatim on purpose.** That's what makes lines-per-slide changes non-destructive — the original breaks are preserved.
- **`number` is advisory.** Nothing enforces "only verses are numbered"; it's just a convention.
- **Read `orderedSongSections`, not raw `songSections`.** The raw relationship set isn't ordered.
