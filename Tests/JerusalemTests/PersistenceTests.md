# `PersistenceTests.swift`

> Proves the SwiftData layer fully saves and restores songs, slides, and playlists across a container reopen — the programmatic stand-in for "quit and relaunch" — and that sample-data seeding happens exactly once.

**Location:** `Tests/JerusalemTests/PersistenceTests.swift`
**Role:** XCTest unit tests (Phase 1 gate — the SwiftData model)

## What it does (plain English)
Phase 1 is the persistence foundation, and the whole reliability promise rests on it: the app autosaves so that a crash or an accidental quit loses nothing. This file proves the durable half of that — it writes real data to an on-disk store, throws away the container, opens a *fresh* container against the *same file*, and checks everything came back intact, including relationships (a playlist that points at a song, the song's slide, the slide's text).

The second test guards `SampleData.seedIfNeeded`, which gives a brand-new install something to show on first launch. It must populate an empty store with exactly one song and one playlist, and — critically — calling it again must not duplicate that data. A non-idempotent seeder would pile up sample songs on every launch.

This is the bedrock the higher phases sit on, so it's deliberately strict about counts and round-trip fidelity.

## XCTest you'll meet in this file
- `final class PersistenceTests: XCTestCase` — the suite.
- `func test...() throws` — tests that may throw; SwiftData calls (`save`, `fetch`) can throw, and a thrown error fails the test.
- `@MainActor` (on the seeding test) — main-thread, required for `ModelContext`.
- `XCTAssertEqual` — `expect(...).toEqual`.
- `XCTUnwrap(x)` — asserts non-nil and returns the value; used to safely grab `items.first`.
- `addTeardownBlock { ... }` — per-test cleanup (like `afterEach`); here it deletes the `.store` file plus its SQLite `-wal`/`-shm` sidecar files.
- `do { ... }` — a plain Swift scope block (not a `try/catch`); used to bound "Session 1" so its `container`/`context` go out of scope before "Session 2" reopens the file. Think of it as deliberately dropping the first DB connection.
- `ModelConfiguration(schema:url:)` vs `ModelConfiguration(isStoredInMemoryOnly: true)` — the first writes to a real file on disk (needed to test reopen); the second is a throwaway in-memory DB.
- `FetchDescriptor<Item>()` — a SwiftData query for all `Item` rows, roughly like `prisma.item.findMany()`.

## The tests, one by one

### `testSongAndPlaylistPersistAcrossReopen`
Picks a unique temp `.store` URL (cleaned up afterward). In a scoped `do` block ("Session 1") it inserts a `song` `Item` carrying one `Slide` with one text `SlideElement`, plus a `Playlist` whose `PlaylistEntry` references that song, then `save()`s. After the block, it opens a brand-new `ModelContainer` against the same file ("Session 2") and verifies the full graph survived:
```swift
let items = try context.fetch(FetchDescriptor<Item>())
XCTAssertEqual(items.count, 1)
let song = try XCTUnwrap(items.first)
XCTAssertEqual(song.title, "Test Song")
XCTAssertEqual(song.kind, .song)
XCTAssertEqual(song.orderedSlides.count, 1)
XCTAssertEqual(song.orderedSlides.first?.orderedElements.first?.text, "a line of lyrics")
```
It then checks the playlist restored too, and that its entry still resolves back to the same song:
```swift
XCTAssertEqual(playlist.orderedEntries.first?.item?.title, "Test Song")
```
**Catches:** data not actually persisting, the enum field (`kind`) not round-tripping (recall enums are stored as a raw string with a computed accessor), nested relationships (slide → element) being lost, or the playlist↔item join (`PlaylistEntry`) breaking across reopen. Any of these would mean a service set vanishing after a relaunch.

### `testSeedingPopulatesEmptyStoreExactlyOnce`
Uses an in-memory store. Calls `SampleData.seedIfNeeded` and asserts exactly one `Item` and one `Playlist` exist. Then calls it **again** and asserts the `Item` count is still one.
```swift
SampleData.seedIfNeeded(context)
XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 1)
// Idempotent: a second call must not duplicate the sample data.
SampleData.seedIfNeeded(context)
XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 1)
```
**Catches:** a seeder that re-seeds on every launch (duplicating the sample song endlessly) or seeds the wrong number of rows on a fresh install.

## How it connects
Exercises `Persistence.schema`, `SampleData.seedIfNeeded`, and the SwiftData models `Item`, `Slide`, `SlideElement`, `Playlist`, `PlaylistEntry` — including the `orderedSlides` / `orderedElements` / `orderedEntries` computed sorts and the `kind` enum accessor. Uses a real on-disk `ModelConfiguration(schema:url:)` for the reopen test.

## What it does NOT cover
It does not test the *app's* autosave behavior in a running process (that's `Persistence.makeContainer`'s autosaving main context, exercised by actually running the app), nor crash recovery under a real crash. It proves the data *can* round-trip through the store; the "autosave-so-nothing-is-lost" promise is verified by use and the dress rehearsal, not by this file.
