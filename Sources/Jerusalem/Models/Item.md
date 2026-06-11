# `Item.swift`

> The top-level library entry — a song, Bible passage, text/sermon, or media clip — plus the ordered slides it produces.

**Location:** `Sources/Jerusalem/Models/Item.swift`
**Role:** SwiftData model + an `ItemKind` enum

## What it does (plain English)
An `Item` is one presentable thing in your library. It might be a song, a Bible passage, a block of sermon/text, or a media clip. The `kind` field says which. Regardless of kind, every `Item` owns an ordered list of `Slide`s — the actual projected pages.

Think of `Item` as the *authored* unit and `Slide` as the *rendered* unit. For songs you author `songSections` (raw lyric blocks); for sermons you author `bodyText`; for Bible items you set a reference string. A separate piece of logic, `ContentRebuilder`, reads that authored content and **materializes** it into the `slides` array. The `Item` also carries kind-specific metadata (CCLI number for songs, a Bible reference/translation, a media filename + video options) — only the fields relevant to its `kind` are used.

It also defines two convenience views over its data: `searchableText` (everything flattened for the library search box) and `aspectRatioValue` (a safe numeric aspect ratio for the renderer).

## Swift you'll meet in this file
- `enum ItemKind: String, Codable, CaseIterable, Identifiable` — a TS-union-like enum. The `String` means each case has a raw string value (`song`, `bible`, …). `Codable` = JSON-serializable for free. `CaseIterable` = you can loop over `.allCases`. `Identifiable` = it has a stable `id` (used by SwiftUI lists).
- `switch self { case .song: "Song" ... }` — pattern matching, like a JS `switch`, but here each case is an expression that returns a value directly.
- `@Model final class` — SwiftData entity, like a Prisma model; `final` = not subclassable.
- `UUID` — a unique-id type. `UUID()` mints a fresh one.
- Optionals: `String?` means `string | null`. `if let subtitle { }` unwraps it (runs only when non-null) and rebinds the same name.
- `private var kindRaw` + a public computed `kind` — the project's enum-storage convention (explained below).
- `@Relationship(deleteRule: .cascade, inverse: \Slide.item)` — a foreign-key relationship; `.cascade` means deleting the `Item` deletes its children; `inverse:` names the property on the other side that points back.
- `[Slide]` — `Slide[]`. Computed `var orderedSlides: [Slide] { ... }` — a getter that returns a sorted copy.
- `guard let raw = aspectRatio else { return ... }` — an early-return null check.
- `CGFloat` / `Double` — floating-point number types.

## Code walkthrough

### The `ItemKind` enum
```swift
enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case song, bible, text, media
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .song:  "Song"
        case .bible: "Bible"
        case .text:  "Text"
        case .media: "Media"
        }
    }
```

Four cases. Because it's a `String` enum, each case automatically has a `rawValue` (`"song"`, etc.). `id` just returns that raw value so SwiftUI can use the kind as a list identity. `displayName` is a computed property mapping each case to a UI label; `symbolName` (just below) maps to an SF Symbols icon name like `"music.note"`. Each `switch` case is an expression returning the string directly — no `return` needed.

### The model and its stored fields
```swift
@Model
final class Item {
    var uuid: UUID = UUID()

    private var kindRaw: String = ItemKind.text.rawValue
    var title: String = ""
    var subtitle: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
```

`uuid` is a stable external id, separate from SwiftData's own internal `persistentModelID` — handy for file naming, export, and sync later. `subtitle` is optional (`String?` = nullable). `createdAt`/`updatedAt` default to "now".

```swift
    var ccli: String?              // song
    var bibleReference: String?    // bible, e.g. "John 3:16-18"
    var bibleTranslation: String?  // bible, e.g. "KJV"
    var mediaFilename: String?     // media (stored under MediaStorage.directory)
    var videoLoops: Bool = false
    var videoMuted: Bool = false
    private var videoEndBehaviorRaw: String = VideoEndBehavior.hold.rawValue
```

These are the kind-specific metadata fields. They're all on one class (not subclasses per kind), and you only use the ones relevant to the current `kind`.

### Authoring fields
```swift
    var linesPerSlide: Int = 2
    var bodyText: String?
    var aspectRatio: String?
```

`linesPerSlide` controls how many lyric/body lines `ContentRebuilder` packs onto a derived slide. `bodyText` holds sermon/text content (songs use `songSections` instead, so `bodyText` stays nil for them). `aspectRatio` is a string like `"16:9"` or `"4:3"`.

### The enum-storage convention (`...Raw` + computed accessor)
This file uses it twice. SwiftData stores primitives cleanly, so enums are persisted as a private raw `String` column, with a public computed property that converts to/from the typed enum:

```swift
private var kindRaw: String = ItemKind.text.rawValue
// ...
var kind: ItemKind {
    get { ItemKind(rawValue: kindRaw) ?? .text }
    set { kindRaw = newValue.rawValue }
}
```

- `kindRaw` is the actual stored column (a `String`), marked `private` so callers can't touch it directly.
- `kind` is the public face. Its `get` rebuilds the enum from the raw string; `ItemKind(rawValue:)` returns an optional (the string might not match a case), and `?? .text` is nullish-coalescing — fall back to `.text` if it's somehow invalid.
- Its `set` writes `newValue.rawValue` back into the raw column. `newValue` is the implicit setter argument, like the value passed to a JS setter.

`videoEndBehavior` follows the exact same pattern over `videoEndBehaviorRaw`.

### Relationships
```swift
@Relationship(deleteRule: .cascade, inverse: \Slide.item)
var slides: [Slide] = []

@Relationship(deleteRule: .cascade, inverse: \SongSection.item)
var songSections: [SongSection] = []

@Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.item)
var playlistEntries: [PlaylistEntry] = []

var theme: Theme?
```

An `Item` owns its `slides`, `songSections`, and `playlistEntries`. `.cascade` means deleting the `Item` deletes all of those children too. `inverse: \Slide.item` points at the `item` property on the `Slide` side (the `\Type.property` syntax is a *key path* — a type-safe reference to a property, like naming a field without reading its value). `theme` is an optional one-way link to a shared `Theme`.

### Constructor and computed views
```swift
init(kind: ItemKind, title: String, subtitle: String? = nil) {
    self.kindRaw = kind.rawValue
    self.title = title
    self.subtitle = subtitle
}
```

Note the constructor takes a typed `ItemKind` but immediately stores its `rawValue`. `subtitle: String? = nil` is a default parameter (same as JS `subtitle = null`).

```swift
var orderedSlides: [Slide] {
    slides.sorted { $0.order < $1.order }
}
```

`slides` is an unordered set from SwiftData's point of view, so this getter returns a copy sorted by each slide's `order`. `$0`/`$1` are shorthand for the two items being compared (like an arrow function `(a, b) => a.order < b.order`). `orderedSongSections` does the same for sections.

```swift
var searchableText: String {
    var parts: [String] = [title]
    if let subtitle { parts.append(subtitle) }
    if let bibleReference { parts.append(bibleReference) }
    for slide in orderedSlides {
        if let label = slide.sectionLabel { parts.append(label) }
        for element in slide.orderedElements where element.kind == .text {
            if let text = element.text { parts.append(text) }
        }
    }
    return parts.joined(separator: "\n")
}
```

This flattens everything text-y about the item into one newline-joined string for the library search box: title, subtitle, Bible reference, plus every slide's label and every text element's text. The clever part: because `ContentRebuilder` already materializes lyrics, sermon body, and Bible text *into* `SlideElement` rows, just walking the slides captures all content uniformly — including manual edits — in a single pass. `if let subtitle { }` is an optional unwrap with no rename (newer Swift shorthand). `where element.kind == .text` filters the loop to text elements only. The actual matching logic lives separately in `LibrarySearch`.

```swift
var aspectRatioValue: CGFloat {
    guard let raw = aspectRatio else { return 16.0 / 9.0 }
    let parts = raw.split(separator: ":")
    if parts.count == 2,
       let w = Double(parts[0]), let h = Double(parts[1]), h > 0 {
        return CGFloat(w / h)
    }
    return 16.0 / 9.0
}
```

Turns the `"16:9"` string into a number for the renderer. `guard let raw = aspectRatio else { return 16.0/9.0 }` bails to a 16:9 default if the field is nil. Otherwise it splits on `:`, and the multi-clause `if` requires *all* conditions: exactly two parts, both parse as `Double`, and the denominator is positive (`h > 0`) — which guarantees the renderer can **never divide by zero**. Anything unparseable falls back to 16:9.

## How it connects
- Owns `[Slide]` (the rendered pages), `[SongSection]` (authored lyrics for songs), and `[PlaylistEntry]` (its memberships in playlists — see `Playlist.swift`).
- Optionally references one `Theme`.
- `ContentRebuilder` (elsewhere) reads `songSections` / `bodyText` / `bibleReference` + `linesPerSlide` and writes the `slides`.
- A `Slide` points back via its `item` property (the relationship inverse).

## Gotchas / why it matters
- **Derived vs. authored:** don't hand-edit `slides` expecting it to be the source of truth for songs/text — it's regenerated from `songSections`/`bodyText` unless a slide is flagged `isManuallyEdited` (see `Slide.swift`).
- **Enum convention:** when adding a new enum-typed field, follow the `private …Raw: String` + computed accessor pattern, or SwiftData persistence gets awkward.
- **Ordered relationships are sorts, not storage:** always read `orderedSlides`/`orderedSongSections`, never the raw `slides`/`songSections` arrays, when order matters.
- **Two ids:** `uuid` is yours to use for files/export; `persistentModelID` is SwiftData's internal handle. Don't conflate them.
