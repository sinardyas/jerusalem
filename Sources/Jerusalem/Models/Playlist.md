# `Playlist.swift`

> A named, ordered set of items for a service — plus the `PlaylistEntry` join model that gives each item its position within that playlist.

**Location:** `Sources/Jerusalem/Models/Playlist.swift`
**Role:** Two SwiftData models — `Playlist` and the `PlaylistEntry` join

## What it does (plain English)
A `Playlist` is a savable running order, like "Sunday AM": the sequence of items you'll project during a service. It replaces the older "setlist" idea, and because it can loop, a looping playlist doubles as a pre-service background loop.

The interesting part is *how* items are attached. An `Item` can appear in **many** playlists, and each playlist needs its **own** ordering of that item. You can't put the order on the `Item` (it would be shared across all playlists) and you can't put it on the `Playlist` directly. So there's a third model in between — `PlaylistEntry` — a **join model** (a many-to-many bridge row). Each `PlaylistEntry` says "this item, at this position, in this playlist." This is exactly the classic relational join table, and the same pattern Prisma calls an explicit many-to-many.

## Swift you'll meet in this file
- `@Model final class` — SwiftData entity (Prisma-model-like); `final` = no `extends`.
- `UUID` / `UUID()` — unique-id type + generator. TS: `string` + `crypto.randomUUID()`.
- `Bool` / `Date` / `Int` — `boolean` / `Date` / `number`.
- `String?`, `Item?`, `Playlist?` — optionals; `T?` = `T | null`.
- `@Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)` — a relationship; `.cascade` ≈ `// @OneToMany(onDelete: Cascade)`; `inverse:` names the back-pointer. `\PlaylistEntry.playlist` is a **key path** (a compiler-checked field reference).
- `[PlaylistEntry]` = `PlaylistEntry[]`.
- Computed `var orderedEntries: [PlaylistEntry] { ... }` = `get orderedEntries(): PlaylistEntry[]`, returning a sorted copy.
- `init(... = false)` — default parameter value, like JS defaults.

## Code walkthrough

### `Playlist`
```swift
@Model
final class Playlist {
    var uuid: UUID = UUID()
    var name: String = "Untitled Playlist"
    var createdAt: Date = Date.now
    var loops: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
    var entries: [PlaylistEntry] = []

    init(name: String, loops: Bool = false) {
        self.name = name
        self.loops = loops
    }

    var orderedEntries: [PlaylistEntry] {
        entries.sorted { $0.order < $1.order }
    }
}
```

**TypeScript equivalent**

```ts
// @Entity
class Playlist {
  uuid: string = crypto.randomUUID();
  name: string = "Untitled Playlist";
  createdAt: Date = new Date();
  loops: boolean = false;

  // @OneToMany(cascade) inverse: PlaylistEntry.playlist
  entries: PlaylistEntry[] = [];

  constructor(name: string, loops: boolean = false) {
    this.name = name;
    this.loops = loops;
  }

  get orderedEntries(): PlaylistEntry[] {
    return [...this.entries].sort((a, b) => a.order - b.order);
  }
}
```

**Swift syntax:**
- `@Model final class` — persisted SwiftData entity (rows), not subclassable. TS: `// @Entity class`.
- `var x: T = v` — mutable stored property with a default.
- `@Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)` — a relationship; `.cascade` deletes children with the parent; `inverse:` is the property on the other side that points back; `\PlaylistEntry.playlist` is a **key path** (type-safe field reference).
- `init(name:, loops: = false)` — constructor with a **default parameter**; called `Playlist(name: "…")`. Argument labels are required.
- `.sorted { $0.order < $1.order }` — returns a new sorted array (non-mutating); `{ }` is a **trailing closure**; `$0`/`$1` are the implicit args. TS: `[...arr].sort((a, b) => a.order - b.order)`.

- `uuid`, `name`, `createdAt`, `loops` are the stored columns. `loops` defaults to `false`; a `true` playlist cycles forever (the pre-service loop trick).
- `entries` is the owned relationship to its join rows. `.cascade` means deleting a `Playlist` deletes its `PlaylistEntry` rows (but **not** the underlying `Item`s — those are independent and may live in other playlists). `inverse: \PlaylistEntry.playlist` points at the `playlist` property on the entry side.
- The constructor takes `name` and an optional `loops` (default `false`).
- `orderedEntries` returns the entries sorted by `order`. `$0`/`$1` are the two compared elements, like `(a, b) => a.order < b.order` in JS. Always read this instead of raw `entries` when sequence matters — SwiftData doesn't guarantee insertion order.

### `PlaylistEntry` (the join model)
```swift
@Model
final class PlaylistEntry {
    var order: Int = 0
    var item: Item?
    var playlist: Playlist?

    init(order: Int) {
        self.order = order
    }
}
```

**TypeScript equivalent**

```ts
// @Entity  (explicit many-to-many join row)
class PlaylistEntry {
  order: number = 0;
  item: Item | null = null;          // inverse of Item.playlistEntries
  playlist: Playlist | null = null;  // inverse of Playlist.entries

  constructor(order: number) {
    this.order = order;
  }
}
```

**Swift syntax:**
- `var item: Item?` — an optional relationship end (`Item | null`). It's nullable because a join row can momentarily exist before both sides are wired, and these are the *inverse* ends of relationships declared elsewhere.

A `PlaylistEntry` is intentionally tiny: just an `order` plus two back-references. `item` points to the `Item` being scheduled; `playlist` points to the `Playlist` it belongs to. Both are optionals (`Item?` / `Playlist?`) because a join row can momentarily exist without both sides wired up, and because these are the *inverse* ends of relationships declared elsewhere:
- `playlist` is the inverse of `Playlist.entries` (declared just above).
- `item` is the inverse of `Item.playlistEntries` (declared in `Item.swift`).

The constructor only requires `order`; you set `item` and `playlist` after creating it.

## How it connects
This is the hub of the item-to-service relationship:
- `Playlist.entries` → many `PlaylistEntry`.
- Each `PlaylistEntry` → one `Item` (and back via `Item.playlistEntries`) and one `Playlist`.
- Net effect: a many-to-many between `Item` and `Playlist`, with a per-playlist `order` carried on the join row. The same `Item` can sit in "Sunday AM" at position 3 and in "Christmas Eve" at position 7 — two separate `PlaylistEntry` rows.

## Gotchas / why it matters
- **Cascade only deletes the join, not the item.** Deleting a `Playlist` removes its `PlaylistEntry` rows; the `Item`s survive (good — they belong to the library, not the service).
- **Order lives on the join, by design.** Don't try to order items via the `Item` itself; that would force one global order across all playlists.
- **Read `orderedEntries`, not `entries`.** The raw set is unordered.
- **Wire both sides.** A `PlaylistEntry` with a nil `item` or nil `playlist` is a dangling row; make sure both ends are set when you create one.
