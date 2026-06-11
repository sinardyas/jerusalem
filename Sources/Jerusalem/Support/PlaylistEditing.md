# `PlaylistEditing.swift`

> A pure namespace of playlist "math" — assigning order numbers, reordering, removing entries, and naming new playlists — kept free of UI so it can be unit-tested.

**Location:** `Sources/Jerusalem/Support/PlaylistEditing.swift`
**Role:** pure-logic namespace

## What it does (plain English)

A playlist is an ordered list of items (songs, readings, etc.), and the ordering is stored as an integer `order` field on each join row (`PlaylistEntry`). This file holds the rules that keep those order numbers correct: what number a new entry gets, how to renumber after a drag-to-reorder, how to renumber after a deletion, and what to call a brand-new playlist.

It's a caseless `enum` — a namespace of pure static functions (`export const PlaylistEditing = { ... }`) — so the rules can be unit-tested without spinning up the UI or a database context. The doc comment is explicit about the philosophy: "the view stays a thin shell that calls into these and then re-arms the live program." One important convention to keep in mind: a playlist reads **top→bottom as first→last**, so `order` runs forward with `top = 0` (the opposite of the front-first Layers panel).

A subtle but real caveat: although this file is "pure math," it does mutate the model objects it's handed (e.g. it appends to `playlist.entries` and rewrites `entry.order`). That's fine because those are reference-type model objects; what it deliberately *doesn't* do is talk to the `ModelContext` — inserting and deleting from the database is left to the caller.

## Swift you'll meet in this file

| Swift | JS/TS meaning |
| --- | --- |
| `enum PlaylistEditing { static func ... }` | A namespace of static functions — no instances |
| `entries.map(\.order).max() ?? -1` | `Math.max(...entries.map(e => e.order))` with `-1` fallback when empty (`??` = nullish coalescing) |
| `@discardableResult` | Caller may ignore the return value without a warning |
| `PlaylistEntry(order: ...)` | Construct a model object; it's a `class` (reference type), so it's shared, not copied |
| `entry.item = item` | Assign a relationship on a reference object |
| `IndexSet`, `to destination: Int` | SwiftUI's "move these rows to here" payload from a list reorder gesture |
| `arr.move(fromOffsets:toOffset:)` | In-place array move helper |
| `for (index, entry) in arr.enumerated()` | `arr.forEach((entry, index) => ...)` |
| `playlist.entries.removeAll { $0 === entry }` | Remove by identity; `===` is reference equality (same object) |

## Code walkthrough

### `nextOrder` — the order for an appended entry

```swift
static func nextOrder(in entries: [PlaylistEntry]) -> Int {
    (entries.map(\.order).max() ?? -1) + 1
}
```

Take the max existing `order`, or `-1` if the playlist is empty, then add one. So the first entry of an empty playlist gets `0`, and each append goes one past the current maximum.

### `makeEntry` — link an item into a playlist

```swift
@discardableResult
static func makeEntry(for item: Item, in playlist: Playlist) -> PlaylistEntry {
    let entry = PlaylistEntry(order: nextOrder(in: playlist.entries))
    entry.item = item
    entry.playlist = playlist
    playlist.entries.append(entry)
    return entry
}
```

It builds a `PlaylistEntry` (the join row between an item and a playlist) at the next free order, wires up both relationships, and appends it to the playlist. It returns the entry so the caller can hand it to the `ModelContext` — the comment is explicit that *inserting into the context is the caller's job*. `@discardableResult` lets callers that don't need the return value skip it cleanly.

### `reorder` — renumber after a drag

```swift
static func reorder(_ ordered: [PlaylistEntry],
                    from source: IndexSet, to destination: Int) {
    var arr = ordered
    arr.move(fromOffsets: source, toOffset: destination)
    for (index, entry) in arr.enumerated() {
        entry.order = index
    }
}
```

SwiftUI hands you `source` (which rows moved) and `destination` (where to). It applies the move to a local copy of the array, then walks the result and rewrites every `order` to its new index. The effect is that `order` stays a gapless `0..<n` with top = first — no holes, no duplicates.

### `remove` — delete and re-pack

```swift
static func remove(_ entry: PlaylistEntry, from playlist: Playlist) {
    playlist.entries.removeAll { $0 === entry }
    for (index, remaining) in playlist.orderedEntries.enumerated() {
        remaining.order = index
    }
}
```

It removes the entry by *identity* (`===`, same object) and then renumbers the survivors so the order sequence has no gap where the removed item was. Again, actually deleting the entry from the `ModelContext` is left to the caller.

### `defaultPlaylistName` — a non-colliding default

```swift
static func defaultPlaylistName(existing: [Playlist]) -> String {
    let base = "Untitled Playlist"
    let taken = Set(existing.map(\.name))
    guard taken.contains(base) else { return base }
    var n = 2
    while taken.contains("\(base) \(n)") { n += 1 }
    return "\(base) \(n)"
}
```

Returns "Untitled Playlist" if free, otherwise "Untitled Playlist 2", "...3", and so on. It builds a `Set` of existing names for fast lookup and counts up until it finds an unused one. This mirrors the "Untitled Song" default elsewhere in the app.

## How it connects

- **Called by** playlist views, which keep themselves thin: they call these functions for the order math, then insert/delete via the `ModelContext` and re-arm the live program.
- **Mutates** the `PlaylistEntry` / `Playlist` reference models it's given, but **never** touches the database context — that boundary is deliberate and is what keeps the functions testable in isolation.
- **Mirrors** `LibrarySearch` and `SlideLayers` as a pure-rule namespace (same project convention).

## Gotchas / why it matters

- **Order is forward, top = 0.** Opposite of the front-first Layers panel. Mixing those conventions up would invert a playlist.
- **Gapless renumbering is invariant.** Both `reorder` and `remove` re-pack `order` to `0..<n`. If you add a mutation path, keep order gapless or sorting elsewhere will break.
- **Caller owns the context.** These functions mutate model relationships but do *not* insert or delete in SwiftData. Forgetting the matching `context.insert` / `context.delete` is the classic bug here.
- **Reference vs value.** Unlike the render snapshots, `PlaylistEntry`/`Playlist` are `class`es (shared references), which is *why* mutating them in place here is visible to the caller. That's intentional, not a leak.
