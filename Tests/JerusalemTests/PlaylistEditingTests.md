# `PlaylistEditingTests.swift`

> Verifies the pure playlist math (next-order, link/append, gapless reorder and removal, default-name de-duplication), a persistence round-trip proving order survives a reopen and that deleting a playlist cascades to its entries but spares the shared items, and that the grouped program lines up with the flat live program.

**Location:** `Tests/JerusalemTests/PlaylistEditingTests.swift`
**Role:** XCTest unit tests (playlist-management gate)

## What it does (plain English)
A playlist is the order of service. This file pins down the rules for building and editing one without surprises: appending an item gets the next order number, dragging an entry rewrites orders so they stay contiguous (no gaps), removing one renumbers the rest, and new playlists get an auto-incrementing default name. These are extracted into the pure `PlaylistEditing` namespace precisely so they can be unit-tested without UI.

It then does a SwiftData round-trip to prove two persistence guarantees that matter when you delete things: a reordered playlist comes back in the new order after a reopen, and deleting a playlist removes its `PlaylistEntry` join rows but leaves the underlying `Item`s alone — because items are *shared* across playlists (the same song can appear in many services). Deleting Sunday's set must never delete the song itself.

Finally, two tests cover `LiveState.groupedProgram`, which powers the grouped grid the operator clicks through. The key property: flattening the groups gives back exactly the flat armed program (same ids, same order), so clicking a slide in the grouped view goes live on the right slide. A duplicate item across two entries must form two distinct groups.

## XCTest you'll meet in this file
- `final class PlaylistEditingTests: XCTestCase` — the suite.
- `func test...()` / `func test...() throws` — test cases; the `throws` ones do SwiftData work.
- `@MainActor` — main-thread (SwiftData / `LiveState`) tests.
- `XCTAssertEqual` / `XCTAssertTrue` / `XCTAssertFalse` / `XCTAssertNotEqual` — `expect(...)` equivalents.
- `XCTUnwrap(x)` — assert non-nil and unwrap.
- `===` — identity (same object reference), like JS `===` on objects; used to assert a returned entry is the *same instance* as the song it links.
- `addTeardownBlock { ... }` — per-test cleanup; deletes the temp `.store` and its `-wal`/`-shm` sidecars.
- `do { ... }` blocks — plain scopes used to bound each "Session" so one container/context is dropped before the next reopens the file.
- `IndexSet(integer: 2)` — a set of indices, the shape SwiftUI's `.onMove` reorder hands you (the source row(s)); `to:` is the drop index.
- `FetchDescriptor<T>()` + `fetchCount` — query all rows of a model / count them.

## The tests, one by one

### `testNextOrderOnEmptyIsZero`
`PlaylistEditing.nextOrder(in: [])` returns `0`.
```swift
XCTAssertEqual(PlaylistEditing.nextOrder(in: []), 0)
```

**TypeScript equivalent (Jest)**

```ts
expect(PlaylistEditing.nextOrder([])).toEqual(0);
```

**Swift syntax:**
- `final class PlaylistEditingTests: XCTestCase` — shape: subclass = test suite. Jest: `describe("PlaylistEditingTests", () => { … })`.
- `PlaylistEditing.nextOrder(in: [])` — shape: `in:` is the argument label; `[]` is an empty array literal. Jest: positional `nextOrder([])`.

**Catches:** the first item in a fresh playlist getting a non-zero order.

### `testNextOrderIsMaxPlusOne`
For entries with orders `0,1,2` it returns `3`; for a single entry at order `5` it returns `6` — proving it's `max + 1`, robust to gaps, not just `count`.
```swift
XCTAssertEqual(PlaylistEditing.nextOrder(in: [PlaylistEntry(order: 5)]), 6)
```

**TypeScript equivalent (Jest)**

```ts
const entries = [new PlaylistEntry({ order: 0 }), new PlaylistEntry({ order: 1 }), new PlaylistEntry({ order: 2 })];
expect(PlaylistEditing.nextOrder(entries)).toEqual(3);
// Robust to gaps / non-contiguous orders.
expect(PlaylistEditing.nextOrder([new PlaylistEntry({ order: 5 })])).toEqual(6);
```

**Catches:** using `count` instead of `max+1`, which would collide order numbers after a removal left a gap.

### `testMakeEntryLinksAndAppendsAtNextOrder`
`makeEntry(for:in:)` for a song into a playlist returns an entry at order `0`, with `entry.item === song` and `entry.playlist === playlist` (both relationship sides wired), and the playlist now has one entry. A second entry lands at order `1`, and the ordered titles read `["Amazing Grace", "John 3:16"]`.
```swift
XCTAssertTrue(first.item === song)
XCTAssertTrue(first.playlist === playlist)
```

**TypeScript equivalent (Jest)**

```ts
const first = PlaylistEditing.makeEntry(song, playlist);
expect(first.order).toEqual(0);
// analogy: Swift `===` (reference identity) ≈ JS `===` on objects (or expect(...).toBe(...)).
expect(first.item === song).toBe(true);
expect(first.playlist === playlist).toBe(true);
expect(playlist.entries.length).toEqual(1);

const second = PlaylistEditing.makeEntry(bible, playlist);
expect(second.order).toEqual(1);
// analogy: Swift trailing-closure .map { $0.item?.title } ≈ .map(e => e.item?.title).
expect(playlist.orderedEntries.map((e) => e.item?.title)).toEqual(["Amazing Grace", "John 3:16"]);
```

**Swift syntax:**
- `a === b` — shape: *identity* comparison — same object instance, not merely equal values. Jest: `===`/`Object.is` on objects (or `expect(a).toBe(b)`).
- `playlist.orderedEntries.map { $0.item?.title }` — shape: a *trailing closure* (the `{ … }` is the closure argument written after the call), where `$0` is the implicit first parameter. Jest: `.map(e => e.item?.title)`.

**Catches:** an entry not appearing in the playlist, a one-sided relationship, or appended items landing out of order.

### `testReorderRewritesOrderForwardGapless`
Given running order `[a,b,c]`, dragging `c` (index 2) to the top (0) yields orders `c=0, a=1, b=2` — i.e. the new arrangement `[c,a,b]` with gapless orders.
```swift
PlaylistEditing.reorder([a, b, c], from: IndexSet(integer: 2), to: 0)
XCTAssertEqual(c.order, 0)
XCTAssertEqual(a.order, 1)
XCTAssertEqual(b.order, 2)
```

**TypeScript equivalent (Jest)**

```ts
// analogy: IndexSet(integer: 2) ≈ the source indices SwiftUI's .onMove hands you, here new Set([2]).
PlaylistEditing.reorder([a, b, c], new Set([2]), 0); // drag c (index 2) to the top
expect(c.order).toEqual(0);
expect(a.order).toEqual(1);
expect(b.order).toEqual(2);
```

**Swift syntax:**
- `IndexSet(integer: 2)` — shape: a set of integer indices; here the single source row `2`. It's the type SwiftUI's `.onMove(from:to:)` passes for the dragged rows. Jest analog: `new Set([2])` (or just `[2]`).

**Catches:** reorder leaving stale or non-contiguous order numbers, which would corrupt the running order.

### `testReorderMovesTopEntryDown`
Dragging `a` (index 0) to the end (index 3) yields `b=0, c=1, a=2` — `[b,c,a]`. This is the SwiftUI `.onMove` convention where the `to:` index is one past the last for an "append" move.
```swift
PlaylistEditing.reorder([a, b, c], from: IndexSet(integer: 0), to: 3)
XCTAssertEqual(b.order, 0)
XCTAssertEqual(c.order, 1)
XCTAssertEqual(a.order, 2)
```

**TypeScript equivalent (Jest)**

```ts
PlaylistEditing.reorder([a, b, c], new Set([0]), 3); // drag a to the end (to: is one past last)
expect(b.order).toEqual(0);
expect(c.order).toEqual(1);
expect(a.order).toEqual(2);
```

**Catches:** off-by-one handling of the move destination index.

### `testRemoveDropsEntryAndRenumbersGapless`
Removes the *middle* of three entries via `PlaylistEditing.remove(_:from:)`. Asserts the playlist now has two entries, the removed one is gone, and the survivors' orders are `[0, 1]` (gapless) with the right entries first and last.
```swift
XCTAssertEqual(playlist.orderedEntries.map(\.order), [0, 1], "remaining orders stay gapless")
```

**TypeScript equivalent (Jest)**

```ts
const entries = [0, 1, 2].map((i) => {
  const e = new PlaylistEntry({ order: i });
  e.playlist = playlist;
  return e;
});
playlist.entries = entries;

PlaylistEditing.remove(entries[1], playlist); // remove the middle one
expect(playlist.entries.length).toEqual(2);
expect(playlist.entries.some((e) => e === entries[1])).toBe(false); // .contains { $0 === entries[1] }
// analogy: Swift key path `\.order` in .map(\.order) ≈ .map(e => e.order).
expect(playlist.orderedEntries.map((e) => e.order)).toEqual([0, 1]); // remaining orders stay gapless
expect(playlist.orderedEntries[0] === entries[0]).toBe(true);
expect(playlist.orderedEntries.at(-1) === entries[2]).toBe(true);
```

**Swift syntax:**
- `PlaylistEditing.remove(_:from:)` — shape: `_` = the first argument has no label (positional), `from:` keeps its label. Jest: `remove(entry, playlist)`.
- `.map(\.order)` — shape: `\.order` is a *key path* — shorthand for `{ $0.order }`. Jest: `.map(e => e.order)`.
- `playlist.entries.contains { $0 === entries[1] }` — shape: `.contains { … }` with a trailing closure and `$0`. Jest: `arr.some(e => e === entries[1])`.
- `XCTAssertEqual(a, b, "message")` — shape: the trailing string is a failure message. Jest: `expect(a).toEqual(b)` (message lives in the test name/comment).

**Catches:** removal leaving a hole in the order sequence (e.g. surviving orders `[0, 2]`), which would later confuse `nextOrder` and reorder math.

### `testDefaultPlaylistNameDedupes`
`defaultPlaylistName(existing:)` returns `"Untitled Playlist"` when none exist, `"Untitled Playlist 2"` when that base name is taken, `"Untitled Playlist 3"` when 1 and 2 exist, and ignores unrelated names (a playlist named `"Sunday AM"` doesn't push the base name up).
```swift
XCTAssertEqual(PlaylistEditing.defaultPlaylistName(existing: two), "Untitled Playlist 3")
```

**TypeScript equivalent (Jest)**

```ts
expect(PlaylistEditing.defaultPlaylistName([])).toEqual("Untitled Playlist");
const one = [new Playlist({ name: "Untitled Playlist" })];
expect(PlaylistEditing.defaultPlaylistName(one)).toEqual("Untitled Playlist 2");
const two = [new Playlist({ name: "Untitled Playlist" }), new Playlist({ name: "Untitled Playlist 2" })];
expect(PlaylistEditing.defaultPlaylistName(two)).toEqual("Untitled Playlist 3");
// Unrelated names don't shadow the base.
expect(PlaylistEditing.defaultPlaylistName([new Playlist({ name: "Sunday AM" })])).toEqual("Untitled Playlist");
```

**Catches:** two playlists ending up with the identical default name, or the dedup counter being thrown off by unrelated names.

### `testReorderPersistsAndDeleteKeepsItems` (the persistence round-trip)
Three sessions over a real on-disk store. **Session 1:** insert two songs `First`/`Second`, add both to a playlist, then reverse the order (`[a,b]` → `[b,a]`) and save. **Session 2:** reopen — assert the order is now `["Second", "First"]` and that there are 2 entries and 2 items; then `delete(playlist)` and save. **Session 3:** reopen and assert:
```swift
XCTAssertEqual(try context.fetchCount(FetchDescriptor<Playlist>()), 0)
XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlaylistEntry>()), 0,
               "deleting a playlist cascade-deletes its entries")
XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 2,
               "shared items are NOT deleted with the playlist")
```

**TypeScript equivalent (Jest)**

```ts
// analogy: FetchDescriptor<T>() + fetchCount ≈ prisma.t.count() for each model.
expect(context.fetchCount(new FetchDescriptor<Playlist>())).toEqual(0);
expect(context.fetchCount(new FetchDescriptor<PlaylistEntry>())).toEqual(0); // entries cascade away
expect(context.fetchCount(new FetchDescriptor<Item>())).toEqual(2);          // shared items survive
```

**Swift syntax:**
- `func testReorderPersistsAndDeleteKeepsItems() throws` — shape: `throws` test doing SwiftData work; a thrown error fails it. Jest: `it("…", () => { … })`.
- `do { … }` — shape: a bare scope block (not try/catch) bounding each "Session" so one container/context drops before the next reopens the file. Jest analog: a `{ … }`/IIFE used to drop references.
- `ModelConfiguration(schema:, url:)` — shape: an *on-disk* store config (real file). Jest analog: a sqlite file path.
- `context.delete(playlist)` then `try context.save()` — shape: stage a delete, then commit. Jest analog: `prisma.playlist.delete(...)`.
- `try context.fetchCount(FetchDescriptor<T>())` — shape: typed count query. Jest analog: `prisma.t.count()`.

**Catches:** reordered order not persisting; and the dangerous case of deleting a playlist also deleting the songs it referenced (data loss) — or, conversely, orphaned `PlaylistEntry` rows lingering after the playlist is gone.

### `testGroupedProgramOneGroupPerEntryMatchesFlatProgram`
Builds a playlist with `First` (2 slides) and `Second` (3 slides). `LiveState.groupedProgram(for:)` returns groups titled `["First", "Second"]` with slide counts `[2, 3]`, and — the load-bearing assertion — flattening the groups' slides yields the same ids in the same order as the flat `LiveState.programSlides(for:)`:
```swift
XCTAssertEqual(groups.flatMap(\.slides).map(\.id),
               LiveState.programSlides(for: playlist).map(\.id),
               "flattened groups == flat program, same order/ids")
```

**TypeScript equivalent (Jest)**

```ts
const groups = LiveState.groupedProgram(playlist);
expect(groups.map((g) => g.title)).toEqual(["First", "Second"]);
expect(groups.map((g) => g.slides.length)).toEqual([2, 3]);
// analogy: Swift .flatMap(\.slides) ≈ .flatMap(g => g.slides); \.id ≈ s => s.id.
expect(groups.flatMap((g) => g.slides).map((s) => s.id)).toEqual(
  LiveState.programSlides(playlist).map((s) => s.id),
); // flattened groups == flat program, same order/ids
```

**Swift syntax:**
- `@MainActor` — shape: main-thread test (SwiftData + `LiveState`). Jest: `// runs on the main thread`.
- `Persistence.makeContainer(inMemory: true)` — shape: builds the app's container in throwaway in-memory mode. `// analogy:` an in-memory SQLite DB (`:memory:`).
- `func makeSong(_ title: String, slides count: Int) -> Item` — shape: a *nested local function*; `slides count:` gives the parameter an external label `slides` and internal name `count`. Jest: a closure `makeSong(title, count)`.
- `.flatMap(\.slides)` — shape: `flatMap` maps then concatenates the resulting arrays; `\.slides` is the key path `{ $0.slides }`. Jest: `.flatMap(g => g.slides)`.
- `.map(\.id)` — shape: key-path map. Jest: `.map(s => s.id)`.

**Catches:** the grouped grid and the live program diverging — which would make clicking a slide in the grouped view go live on the *wrong* slide.

### `testGroupedProgramDuplicateItemFormsTwoGroups`
Adds the *same* song to a playlist twice. Asserts `groupedProgram` returns 2 groups, both titled `"Repeat"`, with **distinct** group ids keyed on the entry (not the item).
```swift
XCTAssertNotEqual(groups[0].id, groups[1].id, "groups keyed on distinct entry ids")
```

**TypeScript equivalent (Jest)**

```ts
const groups = LiveState.groupedProgram(playlist);
expect(groups.length).toEqual(2); // same item in two entries → two groups
expect(groups.map((g) => g.title)).toEqual(["Repeat", "Repeat"]);
expect(groups[0].id).not.toEqual(groups[1].id); // groups keyed on distinct entry ids
```

**Swift syntax:**
- `XCTAssertNotEqual(a, b, "message")` — shape: passes when `a != b`; trailing string is the failure message. Jest: `expect(a).not.toEqual(b)`.

**Catches:** de-duplicating a song that legitimately appears twice (e.g. an opening and closing reprise), which would collapse two service moments into one.

## How it connects
Exercises the pure `PlaylistEditing` namespace (`nextOrder`, `makeEntry`, `reorder`, `remove`, `defaultPlaylistName`) and `LiveState.groupedProgram` / `LiveState.programSlides`. Models touched: `Playlist`, `PlaylistEntry` (the join), `Item`, `Slide`, `SlideElement`, plus `orderedEntries`. Uses both an on-disk store (round-trip) and `Persistence.makeContainer(inMemory: true)` (grouped-program tests).

## What it does NOT cover
The drag-and-drop UI itself and the SwiftUI `.onMove`/`List` wiring aren't tested — only the pure functions those gestures call. The grouped grid's rendering and click-to-go-live interaction are likewise programmatic here (id alignment), with the actual on-screen behavior left to running the app.

## XCTest → Jest glossary
- `final class X: XCTestCase { }` — shape: subclass = test suite. Jest: `describe("X", () => { … })`.
- `func testFoo()` / `func testFoo() throws` — shape: `test`-prefixed, may throw → can fail. Jest: `it("foo", () => { … })`.
- `@MainActor` — shape: main-thread run (SwiftData / `LiveState`). Jest: `// runs on the main thread`.
- `XCTAssertEqual / XCTAssertNotEqual(a, b)` — Jest: `expect(a).toEqual(b)` / `.not.toEqual(b)`.
- `XCTAssertTrue / XCTAssertFalse(x)` — Jest: `expect(x).toBe(true)` / `.toBe(false)`.
- `XCTUnwrap(x)` — shape: assert non-nil **and** return the value. Jest: `expect(x).toBeDefined(); const v = x!;`.
- `===` — shape: reference identity. Jest: `===`/`Object.is` (or `expect(a).toBe(b)`).
- `addTeardownBlock { … }` — shape: register post-test cleanup. Jest: `afterEach(() => …)`.
- `do { … }` — shape: a bare scope block (not try/catch) to bound lifetimes. Jest: a `{ … }`/IIFE that drops references.
- `IndexSet(integer: n)` — shape: a set of integer indices (the `.onMove` source rows). Jest: `new Set([n])`.
- `\.order` / `.map(\.order)` / `.flatMap(\.slides)` — shape: key-path shorthand for a one-property closure. Jest: `.map(e => e.order)` / `.flatMap(g => g.slides)`.
- `{ $0.foo }` (trailing closure) — shape: anonymous closure, `$0` = first arg. Jest: `e => e.foo`.
- `_` argument label — shape: positional (no call-site label). Jest: a plain positional parameter.
- `ModelContainer` / `ModelContext` / `ModelConfiguration` / `FetchDescriptor<T>()` / `fetchCount` — shape: store / session / config / typed fetch-all / count. Jest analog: DB connection / unit-of-work / options / `prisma.t.findMany()` / `prisma.t.count()`.
- `Persistence.makeContainer(inMemory: true)` — shape: app container in in-memory mode. `// analogy:` in-memory SQLite (`:memory:`).
