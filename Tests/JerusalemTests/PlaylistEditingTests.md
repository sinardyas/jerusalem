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
**Catches:** the first item in a fresh playlist getting a non-zero order.

### `testNextOrderIsMaxPlusOne`
For entries with orders `0,1,2` it returns `3`; for a single entry at order `5` it returns `6` — proving it's `max + 1`, robust to gaps, not just `count`.
```swift
XCTAssertEqual(PlaylistEditing.nextOrder(in: [PlaylistEntry(order: 5)]), 6)
```
**Catches:** using `count` instead of `max+1`, which would collide order numbers after a removal left a gap.

### `testMakeEntryLinksAndAppendsAtNextOrder`
`makeEntry(for:in:)` for a song into a playlist returns an entry at order `0`, with `entry.item === song` and `entry.playlist === playlist` (both relationship sides wired), and the playlist now has one entry. A second entry lands at order `1`, and the ordered titles read `["Amazing Grace", "John 3:16"]`.
```swift
XCTAssertTrue(first.item === song)
XCTAssertTrue(first.playlist === playlist)
```
**Catches:** an entry not appearing in the playlist, a one-sided relationship, or appended items landing out of order.

### `testReorderRewritesOrderForwardGapless`
Given running order `[a,b,c]`, dragging `c` (index 2) to the top (0) yields orders `c=0, a=1, b=2` — i.e. the new arrangement `[c,a,b]` with gapless orders.
**Catches:** reorder leaving stale or non-contiguous order numbers, which would corrupt the running order.

### `testReorderMovesTopEntryDown`
Dragging `a` (index 0) to the end (index 3) yields `b=0, c=1, a=2` — `[b,c,a]`. This is the SwiftUI `.onMove` convention where the `to:` index is one past the last for an "append" move.
**Catches:** off-by-one handling of the move destination index.

### `testRemoveDropsEntryAndRenumbersGapless`
Removes the *middle* of three entries via `PlaylistEditing.remove(_:from:)`. Asserts the playlist now has two entries, the removed one is gone, and the survivors' orders are `[0, 1]` (gapless) with the right entries first and last.
```swift
XCTAssertEqual(playlist.orderedEntries.map(\.order), [0, 1], "remaining orders stay gapless")
```
**Catches:** removal leaving a hole in the order sequence (e.g. surviving orders `[0, 2]`), which would later confuse `nextOrder` and reorder math.

### `testDefaultPlaylistNameDedupes`
`defaultPlaylistName(existing:)` returns `"Untitled Playlist"` when none exist, `"Untitled Playlist 2"` when that base name is taken, `"Untitled Playlist 3"` when 1 and 2 exist, and ignores unrelated names (a playlist named `"Sunday AM"` doesn't push the base name up).
```swift
XCTAssertEqual(PlaylistEditing.defaultPlaylistName(existing: two), "Untitled Playlist 3")
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
**Catches:** reordered order not persisting; and the dangerous case of deleting a playlist also deleting the songs it referenced (data loss) — or, conversely, orphaned `PlaylistEntry` rows lingering after the playlist is gone.

### `testGroupedProgramOneGroupPerEntryMatchesFlatProgram`
Builds a playlist with `First` (2 slides) and `Second` (3 slides). `LiveState.groupedProgram(for:)` returns groups titled `["First", "Second"]` with slide counts `[2, 3]`, and — the load-bearing assertion — flattening the groups' slides yields the same ids in the same order as the flat `LiveState.programSlides(for:)`:
```swift
XCTAssertEqual(groups.flatMap(\.slides).map(\.id),
               LiveState.programSlides(for: playlist).map(\.id),
               "flattened groups == flat program, same order/ids")
```
**Catches:** the grouped grid and the live program diverging — which would make clicking a slide in the grouped view go live on the *wrong* slide.

### `testGroupedProgramDuplicateItemFormsTwoGroups`
Adds the *same* song to a playlist twice. Asserts `groupedProgram` returns 2 groups, both titled `"Repeat"`, with **distinct** group ids keyed on the entry (not the item).
```swift
XCTAssertNotEqual(groups[0].id, groups[1].id, "groups keyed on distinct entry ids")
```
**Catches:** de-duplicating a song that legitimately appears twice (e.g. an opening and closing reprise), which would collapse two service moments into one.

## How it connects
Exercises the pure `PlaylistEditing` namespace (`nextOrder`, `makeEntry`, `reorder`, `remove`, `defaultPlaylistName`) and `LiveState.groupedProgram` / `LiveState.programSlides`. Models touched: `Playlist`, `PlaylistEntry` (the join), `Item`, `Slide`, `SlideElement`, plus `orderedEntries`. Uses both an on-disk store (round-trip) and `Persistence.makeContainer(inMemory: true)` (grouped-program tests).

## What it does NOT cover
The drag-and-drop UI itself and the SwiftUI `.onMove`/`List` wiring aren't tested — only the pure functions those gestures call. The grouped grid's rendering and click-to-go-live interaction are likewise programmatic here (id alignment), with the actual on-screen behavior left to running the app.
