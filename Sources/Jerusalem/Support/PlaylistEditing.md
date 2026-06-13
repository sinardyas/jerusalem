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
| `enum PlaylistEditing { static func ... }` | A **caseless enum** namespace of static functions — no instances ≈ `export const PlaylistEditing = { ... }` |
| `entries.map(\.order).max() ?? -1` | `Math.max(...entries.map(e => e.order))` with `-1` fallback when empty; `\.order` is a **key path** ≈ `e => e.order`; `??` = nullish coalescing |
| `@discardableResult` | Caller may ignore the return value without a warning (no TS equivalent) |
| `PlaylistEntry(order: ...)` | Construct a model object — it's a `class` (reference type), so it's shared, not copied |
| `entry.item = item` | Assign a relationship on a reference object |
| `IndexSet`, `to destination: Int` | SwiftUI's "move these rows to here" payload from a list reorder gesture |
| `arr.move(fromOffsets:toOffset:)` | In-place array move helper (mutates `arr`) |
| `for (index, entry) in arr.enumerated()` | `arr.forEach((entry, index) => ...)` — `enumerated()` pairs each element with its index |
| `playlist.entries.removeAll { $0 === entry }` | Remove by identity; `===` is reference equality (same object instance) |

## Code walkthrough

### `nextOrder` — the order for an appended entry

```swift
static func nextOrder(in entries: [PlaylistEntry]) -> Int {
    (entries.map(\.order).max() ?? -1) + 1
}
```

**TypeScript equivalent**

```ts
function nextOrder(entries: PlaylistEntry[]): number {
  const max = entries.length ? Math.max(...entries.map(e => e.order)) : -1; // ?? -1
  return max + 1;
}
```

Take the max existing `order`, or `-1` if the playlist is empty, then add one. So the first entry of an empty playlist gets `0`, and each append goes one past the current maximum.

**Swift syntax:**
- `enum PlaylistEditing { static func ... }` — caseless enum as a namespace; `static func` is called as `PlaylistEditing.nextOrder(...)`.
- `entries.map(\.order)` — `\.order` is a **key path** standing in for the closure `e => e.order`; `.map(\.order)` is `entries.map(e => e.order)`.
- `.max() ?? -1` — `.max()` returns an optional (`nil` for an empty array); `?? -1` supplies the fallback.
- The function body is a single expression, so its value is returned implicitly (no `return` keyword).

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

**TypeScript equivalent**

```ts
// @discardableResult: callers may ignore the returned entry without a lint warning.
function makeEntry(item: Item, playlist: Playlist): PlaylistEntry {
  const entry = new PlaylistEntry({ order: nextOrder(playlist.entries) });
  entry.item = item;               // wire up both relationship sides
  entry.playlist = playlist;
  playlist.entries.push(entry);    // mutate the (reference-type) model in place
  return entry;                    // caller does context.insert(entry)
}
```

It builds a `PlaylistEntry` (the join row between an item and a playlist) at the next free order, wires up both relationships, and appends it to the playlist. It returns the entry so the caller can hand it to the `ModelContext` — the comment is explicit that *inserting into the context is the caller's job*. `@discardableResult` lets callers that don't need the return value skip it cleanly.

**Swift syntax:**
- `@discardableResult` — an attribute that silences the "unused return value" warning, so callers may ignore the result. No TS equivalent (TS never warns about ignored returns).
- `PlaylistEntry(order: ...)` — constructs a **class** instance (reference type). Because it's a reference, the mutations below (`entry.item = ...`, `playlist.entries.append(...)`) are visible to the caller — that's intentional, and the whole reason these "pure" helpers can mutate in place.

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

**TypeScript equivalent**

```ts
// source/destination come from SwiftUI's list-move gesture.
function reorder(ordered: PlaylistEntry[], source: IndexSet, destination: number): void {
  const arr = [...ordered];                      // var arr = ordered (value copy)
  arrayMove(arr, source, destination);           // arr.move(fromOffsets:toOffset:)
  arr.forEach((entry, index) => {                // for (index, entry) in arr.enumerated()
    entry.order = index;                         // gapless 0..<n, top = first
  });
}
```

SwiftUI hands you `source` (which rows moved) and `destination` (where to). It applies the move to a local copy of the array, then walks the result and rewrites every `order` to its new index. The effect is that `order` stays a gapless `0..<n` with top = first — no holes, no duplicates.

**Swift syntax:**
- `from source: IndexSet, to destination: Int` — external labels `from`/`to` with internal names `source`/`destination`; the call site reads `reorder(x, from: s, to: d)`.
- `var arr = ordered` — copies the **array** (arrays are value types in Swift, so `arr` is an independent copy) — but the *elements* are class references, so rewriting `entry.order` still mutates the shared models.
- `for (index, entry) in arr.enumerated()` — `.enumerated()` yields `(index, element)` **tuples**; destructured into `index` and `entry`, like `arr.forEach((entry, index) => ...)`.

### `remove` — delete and re-pack

```swift
static func remove(_ entry: PlaylistEntry, from playlist: Playlist) {
    playlist.entries.removeAll { $0 === entry }
    for (index, remaining) in playlist.orderedEntries.enumerated() {
        remaining.order = index
    }
}
```

**TypeScript equivalent**

```ts
function remove(entry: PlaylistEntry, playlist: Playlist): void {
  // removeAll { $0 === entry }: filter out by identity (same object)
  playlist.entries = playlist.entries.filter(e => e !== entry);
  // renumber survivors so order has no gap
  playlist.orderedEntries.forEach((remaining, index) => {
    remaining.order = index;
  });
}
```

It removes the entry by *identity* (`===`, same object) and then renumbers the survivors so the order sequence has no gap where the removed item was. Again, actually deleting the entry from the `ModelContext` is left to the caller.

**Swift syntax:**
- `removeAll { $0 === entry }` — `.removeAll(where:)` with a trailing closure; `$0` is each element. `===` is **reference (identity) equality** — "is this the very same object?" — distinct from `==` (value equality). The TS analog is `!==`/`===` on object references.

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

**TypeScript equivalent**

```ts
function defaultPlaylistName(existing: Playlist[]): string {
  const base = "Untitled Playlist";
  const taken = new Set(existing.map(p => p.name));   // Set for fast lookup
  if (!taken.has(base)) return base;                  // guard ... else return base
  let n = 2;
  while (taken.has(`${base} ${n}`)) n += 1;           // "\(base) \(n)" interpolation
  return `${base} ${n}`;
}
```

Returns "Untitled Playlist" if free, otherwise "Untitled Playlist 2", "...3", and so on. It builds a `Set` of existing names for fast lookup and counts up until it finds an unused one. This mirrors the "Untitled Song" default elsewhere in the app.

**Swift syntax:**
- `Set(existing.map(\.name))` — `Set(...)` builds a hash set from the mapped names; `\.name` is the key-path shorthand again.
- `guard taken.contains(base) else { return base }` — guard reads "I require the base name to be taken, else just return it"; only past the guard do we need to append a number.
- `"\(base) \(n)"` — **string interpolation**: `\(expr)` embeds a value, exactly like a JS template literal `${expr}`.
- `var n = 2` / `n += 1` — a mutable counter (`let n` would forbid the `+= 1`).

## How it connects

- **Called by** playlist views, which keep themselves thin: they call these functions for the order math, then insert/delete via the `ModelContext` and re-arm the live program.
- **Mutates** the `PlaylistEntry` / `Playlist` reference models it's given, but **never** touches the database context — that boundary is deliberate and is what keeps the functions testable in isolation.
- **Mirrors** `LibrarySearch` and `SlideLayers` as a pure-rule namespace (same project convention).

## Gotchas / why it matters

- **Order is forward, top = 0.** Opposite of the front-first Layers panel. Mixing those conventions up would invert a playlist.
- **Gapless renumbering is invariant.** Both `reorder` and `remove` re-pack `order` to `0..<n`. If you add a mutation path, keep order gapless or sorting elsewhere will break.
- **Caller owns the context.** These functions mutate model relationships but do *not* insert or delete in SwiftData. Forgetting the matching `context.insert` / `context.delete` is the classic bug here.
- **Reference vs value.** Unlike the render snapshots, `PlaylistEntry`/`Playlist` are `class`es (shared references), which is *why* mutating them in place here is visible to the caller. That's intentional, not a leak.
