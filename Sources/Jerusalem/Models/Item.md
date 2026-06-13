# `Item.swift`

> The top-level library entry — a song, Bible passage, text/sermon, or media clip — plus the ordered slides it produces.

**Location:** `Sources/Jerusalem/Models/Item.swift`
**Role:** SwiftData model + an `ItemKind` enum

## What it does (plain English)
An `Item` is one presentable thing in your library. It might be a song, a Bible passage, a block of sermon/text, or a media clip. The `kind` field says which. Regardless of kind, every `Item` owns an ordered list of `Slide`s — the actual projected pages.

Think of `Item` as the *authored* unit and `Slide` as the *rendered* unit. For songs you author `songSections` (raw lyric blocks); for sermons you author `bodyText`; for Bible items you set a reference string. A separate piece of logic, `ContentRebuilder`, reads that authored content and **materializes** it into the `slides` array. The `Item` also carries kind-specific metadata (CCLI number for songs, a Bible reference/translation, a media filename + video options) — only the fields relevant to its `kind` are used.

It also defines two convenience views over its data: `searchableText` (everything flattened for the library search box) and `aspectRatioValue` (a safe numeric aspect ratio for the renderer).

## Swift you'll meet in this file
- `enum ItemKind: String, Codable, CaseIterable, Identifiable { case song, bible, … }` — a TS-union-like enum. `: String` gives each case a raw string value (`"song"`, …) ≈ `type ItemKind = "song" | "bible" | …`. `Codable` = JSON-serializable for free; `CaseIterable` = `.allCases` (like a TS array of all members); `Identifiable` = has a stable `id` (for SwiftUI lists).
- `switch self { case .song: "Song" … }` — pattern matching where each case is an expression returning a value. TS: `switch`/`return` or a `Record<ItemKind, string>` lookup.
- `@Model final class` — SwiftData entity (Prisma-model-like); `final` = no `extends`.
- `UUID` / `UUID()` — a unique-id type; `UUID()` mints one. TS analog: `string` + `crypto.randomUUID()`.
- Optionals: `String?` = `string | null`. `if let subtitle { }` unwraps it (runs only when non-null) and rebinds the same name ≈ `if (subtitle != null) { … }`.
- `private var kindRaw` + public computed `kind` — the project's enum-storage convention (below). TS: a private `kindRaw: string` backing a `get/set kind()`.
- `@Relationship(deleteRule: .cascade, inverse: \Slide.item)` — a relationship; `.cascade` ≈ `// @OneToMany(onDelete: Cascade)`; `inverse: \Slide.item` ≈ `inverse: Slide.item`.
- `[Slide]` = `Slide[]`; computed `var orderedSlides: [Slide] { ... }` = `get orderedSlides(): Slide[]`.
- `guard let raw = aspectRatio else { return … }` — early-return null check ≈ `if (aspectRatio == null) return …; const raw = aspectRatio;`.
- `CGFloat` / `Double` — floating-point numbers (`number`).
- `\.foo` — a **key path**, a type-safe reference to a property without reading it ≈ naming the field, like `"foo"` but checked by the compiler.

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

**TypeScript equivalent**

```ts
type ItemKind = "song" | "bible" | "text" | "media";

const ItemKind = {
  allCases: ["song", "bible", "text", "media"] as ItemKind[], // CaseIterable
  id: (k: ItemKind): string => k,                              // rawValue
  displayName: (k: ItemKind): string => {
    switch (k) {
      case "song":  return "Song";
      case "bible": return "Bible";
      case "text":  return "Text";
      case "media": return "Media";
    }
  },
};
```

**Swift syntax:**
- `enum Foo: String { case a, b }` — a string-backed enum; each case has a `rawValue` (`a` → `"a"`). TS: a string-literal union `type Foo = "a" | "b"`.
- `Codable` / `CaseIterable` / `Identifiable` — protocols the enum conforms to (like implementing TS interfaces): JSON-serializable, `.allCases`, and "has an `id`".
- `var id: String { rawValue }` — computed property; `rawValue` is the enum's backing string. TS: `get id() { return this }`.
- `switch self { case .song: "Song" … }` — exhaustive switch (the compiler checks every case is handled); each case is a value-returning **expression** (no `return` keyword). `.song` is shorthand for `ItemKind.song` because the type is known.

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

**TypeScript equivalent**

```ts
// @Entity
class Item {
  uuid: string = crypto.randomUUID();

  private kindRaw: string = "text";       // ItemKind.text.rawValue
  title: string = "";
  subtitle: string | null = null;         // String?
  createdAt: Date = new Date();
  updatedAt: Date = new Date();
}
```

**Swift syntax:**
- `var subtitle: String?` — an **optional**: `String | null/undefined`. No default means it defaults to `nil`.
- `private var kindRaw` — `private` limits access to this type only, so callers can't touch the raw column directly.
- `Date.now` — the current timestamp. TS: `new Date()`.

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

**TypeScript equivalent**

```ts
  ccli: string | null = null;             // song
  bibleReference: string | null = null;   // bible, e.g. "John 3:16-18"
  bibleTranslation: string | null = null; // bible, e.g. "KJV"
  mediaFilename: string | null = null;    // media (under MediaStorage.directory)
  videoLoops: boolean = false;
  videoMuted: boolean = false;
  private videoEndBehaviorRaw: string = "hold"; // VideoEndBehavior.hold.rawValue
```

**Swift syntax:**
- `Bool` = `boolean`.

These are the kind-specific metadata fields. They're all on one class (not subclasses per kind), and you only use the ones relevant to the current `kind`.

### Authoring fields
```swift
    var linesPerSlide: Int = 2
    var bodyText: String?
    var aspectRatio: String?
```

**TypeScript equivalent**

```ts
  linesPerSlide: number = 2;
  bodyText: string | null = null;
  aspectRatio: string | null = null;       // "16:9" | "4:3" | null
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

**TypeScript equivalent**

```ts
private kindRaw: string = "text"; // ItemKind.text.rawValue
// ...
get kind(): ItemKind {
  // ItemKind(rawValue:) returns null if the string matches no case → fall back to "text"
  const cases: ItemKind[] = ["song", "bible", "text", "media"];
  return cases.includes(this.kindRaw as ItemKind) ? (this.kindRaw as ItemKind) : "text";
}
set kind(newValue: ItemKind) {
  this.kindRaw = newValue; // newValue.rawValue
}
```

**Swift syntax:**
- `var kind: ItemKind { get { … } set { … } }` — a computed property with **both** a getter and setter. TS: `get kind()` + `set kind(newValue)`.
- `Enum(rawValue: someString)` — a **failable initializer**: builds the enum from a string, returning an *optional* (`nil` if no case matches). TS analog: a lookup that may return `undefined`.
- `?? .text` — **nil-coalescing**: "use the left side, or `.text` if it's nil." TS: `?? "text"`.
- `newValue` — the implicit setter argument (the value being assigned). TS: the `newValue` parameter of `set`.

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

**TypeScript equivalent**

```ts
  // @OneToMany(cascade) inverse: Slide.item
  slides: Slide[] = [];

  // @OneToMany(cascade) inverse: SongSection.item
  songSections: SongSection[] = [];

  // @OneToMany(cascade) inverse: PlaylistEntry.item
  playlistEntries: PlaylistEntry[] = [];

  theme: Theme | null = null;             // optional, non-cascading
```

**Swift syntax:**
- `@Relationship(deleteRule: .cascade, inverse: \Slide.item)` — declares a relationship. `.cascade` = deleting the parent deletes children. `inverse:` names the property on the *other* side that points back. TS: `// @OneToMany(cascade) inverse: Slide.item`.
- `\Slide.item` — a **key path**: a type-safe reference to the `item` property of `Slide`, without reading any instance. Think of it as the compiler-checked name of a field.
- `[Slide] = []` — an array property defaulting to empty. TS: `Slide[] = []`.

An `Item` owns its `slides`, `songSections`, and `playlistEntries`. `.cascade` means deleting the `Item` deletes all of those children too. `inverse: \Slide.item` points at the `item` property on the `Slide` side (the `\Type.property` syntax is a *key path* — a type-safe reference to a property, like naming a field without reading its value). `theme` is an optional one-way link to a shared `Theme`.

### Constructor and computed views
```swift
init(kind: ItemKind, title: String, subtitle: String? = nil) {
    self.kindRaw = kind.rawValue
    self.title = title
    self.subtitle = subtitle
}
```

**TypeScript equivalent**

```ts
constructor(kind: ItemKind, title: string, subtitle: string | null = null) {
  this.kindRaw = kind;   // kind.rawValue
  this.title = title;
  this.subtitle = subtitle;
}
```

**Swift syntax:**
- `subtitle: String? = nil` — a **default parameter**. TS: `subtitle: string | null = null`. Callers may omit it.
- Argument labels again: this is called `Item(kind: .song, title: "…")`.

Note the constructor takes a typed `ItemKind` but immediately stores its `rawValue`. `subtitle: String? = nil` is a default parameter (same as JS `subtitle = null`).

```swift
var orderedSlides: [Slide] {
    slides.sorted { $0.order < $1.order }
}
```

**TypeScript equivalent**

```ts
get orderedSlides(): Slide[] {
  return [...this.slides].sort((a, b) => a.order - b.order);
}
```

**Swift syntax:**
- `.sorted { $0.order < $1.order }` — returns a *new* sorted array (non-mutating; `.sort()` would sort in place). The `{ }` is a **trailing closure** (an inline function); `$0`/`$1` are the implicit first/second arguments. TS: `[...arr].sort((a, b) => a.order - b.order)`. The closure returns a `Bool` (`<`), whereas TS `sort` wants a number — hence `a.order - b.order`.

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

**TypeScript equivalent**

```ts
get searchableText(): string {
  const parts: string[] = [this.title];
  if (this.subtitle != null) parts.push(this.subtitle);
  if (this.bibleReference != null) parts.push(this.bibleReference);
  for (const slide of this.orderedSlides) {
    if (slide.sectionLabel != null) parts.push(slide.sectionLabel);
    for (const element of slide.orderedElements) {
      if (element.kind !== "text") continue;            // where element.kind == .text
      if (element.text != null) parts.push(element.text);
    }
  }
  return parts.join("\n");
}
```

**Swift syntax:**
- `var parts: [String] = [title]` — a mutable local array. TS: `const parts: string[] = [title]` (mutable contents; `var` here means the binding can be reassigned too).
- `if let subtitle { … }` — optional binding shorthand: runs only if `subtitle` is non-nil, reusing the name. TS: `if (subtitle != null) { … }`.
- `for x in collection { … }` — `for…of`. `for element in … where cond` — a loop with a built-in filter; iterations where `cond` is false are skipped (like a `continue` guard).
- `parts.append(x)` = `parts.push(x)`; `.joined(separator: "\n")` = `.join("\n")`.

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

**TypeScript equivalent**

```ts
get aspectRatioValue(): number {
  const raw = this.aspectRatio;
  if (raw == null) return 16.0 / 9.0;                  // guard let … else
  const parts = raw.split(":");
  const w = Number(parts[0]);
  const h = Number(parts[1]);
  if (parts.length === 2 && !isNaN(w) && !isNaN(h) && h > 0) {
    return w / h;
  }
  return 16.0 / 9.0;
}
```

**Swift syntax:**
- `guard let raw = aspectRatio else { return … }` — unwrap-or-bail: if `aspectRatio` is nil, run the `else` (which must exit); otherwise `raw` is the non-nil value, in scope for the rest of the function. TS: `if (aspectRatio == null) return …; const raw = aspectRatio;`.
- `let parts = …` — `let` is an **immutable** binding (`const`); `var` is mutable (`let` in JS).
- Multi-clause `if` with commas — *all* clauses must pass (logical AND). `let w = Double(parts[0])` is a failable conversion that also binds `w` only if it succeeds. TS: chained `&&` with `Number(...)` + `isNaN` checks.
- `CGFloat(w / h)` / `Double(parts[0])` — explicit numeric type conversions (Swift won't auto-convert between number types). TS numbers are all one type, so these vanish.

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
