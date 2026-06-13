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

**TypeScript equivalent (Jest)**

```ts
// analogy: FetchDescriptor<Item>() ≈ prisma.item.findMany() — fetch all Item rows.
const items = context.fetch(new FetchDescriptor<Item>());
expect(items.length).toEqual(1);
expect(items[0]).toBeDefined(); // XCTUnwrap: assert non-null...
const song = items[0]!;         // ...then use the unwrapped value
expect(song.title).toEqual("Test Song");
expect(song.kind).toEqual("song"); // analogy: enum case .song ≈ "song" tag
expect(song.orderedSlides.length).toEqual(1);
expect(song.orderedSlides[0]?.orderedElements[0]?.text).toEqual("a line of lyrics");
```

**Swift syntax:**
- `final class PersistenceTests: XCTestCase` — shape: subclass = test suite. Jest: `describe("PersistenceTests", () => { … })`.
- `func testSongAndPlaylistPersistAcrossReopen() throws` — shape: `test`-prefixed, `throws`-able; a thrown SwiftData error fails it. Jest: `it("…", () => { … })` (errors auto-fail).
- `addTeardownBlock { … }` — shape: register cleanup (trailing closure) to run after the test. Jest: `afterEach(() => …)` inline.
- `let configuration = ModelConfiguration(schema:, url:)` — shape: an *on-disk* store config (a real file, needed to test reopen). Jest analog: a sqlite file path (vs an in-memory DB).
- `do { … }` — shape: a bare scope block (not try/catch) used to bound "Session 1" so its container/context deallocate before Session 2. Jest analog: wrapping setup in a `{ … }` block / IIFE to drop references.
- `let container = try ModelContainer(for:, configurations:)` — shape: open the store; `try` because it can throw. Jest analog: `new ModelContainer(...)`.
- `let items = try context.fetch(FetchDescriptor<Item>())` — shape: `FetchDescriptor<Item>()` is a typed "fetch all `Item`s" query. Jest analog: `prisma.item.findMany()`.
- `let song = try XCTUnwrap(items.first)` — shape: assert `.first` is non-nil and bind the unwrapped value. Jest analog: `expect(x).toBeDefined(); const song = x!;`.
- `song.kind` — shape: a computed accessor over a stored `…Raw: String` (the project's enum-persistence convention); compared to `.song` via leading-dot inference. Jest analog: a string field compared to `"song"`.
- `song.orderedSlides.first?.orderedElements.first?.text` — shape: chained `?.` through optional `.first`s. Jest analog: `slides[0]?.elements[0]?.text`.

It then checks the playlist restored too, and that its entry still resolves back to the same song:
```swift
XCTAssertEqual(playlist.orderedEntries.first?.item?.title, "Test Song")
```

**TypeScript equivalent (Jest)**

```ts
expect(playlist.orderedEntries[0]?.item?.title).toEqual("Test Song");
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

**TypeScript equivalent (Jest)**

```ts
// analogy: in-memory ModelContainer ≈ a fresh in-memory test DB (better-sqlite3 :memory:).
SampleData.seedIfNeeded(context);
expect(context.fetchCount(new FetchDescriptor<Item>())).toEqual(1);
// Idempotent: a second call must not duplicate the sample data.
SampleData.seedIfNeeded(context);
expect(context.fetchCount(new FetchDescriptor<Item>())).toEqual(1);
```

**Swift syntax:**
- `@MainActor` — shape: pins the test to the main thread (required for `ModelContext`). Jest: `// runs on the main thread`.
- `ModelConfiguration(isStoredInMemoryOnly: true)` — shape: a throwaway in-memory store. `// analogy:` an in-memory SQLite DB (`:memory:`).
- `try context.fetchCount(FetchDescriptor<Item>())` — shape: count rows without materializing them. Jest analog: `prisma.item.count()`.

**Catches:** a seeder that re-seeds on every launch (duplicating the sample song endlessly) or seeds the wrong number of rows on a fresh install.

## How it connects
Exercises `Persistence.schema`, `SampleData.seedIfNeeded`, and the SwiftData models `Item`, `Slide`, `SlideElement`, `Playlist`, `PlaylistEntry` — including the `orderedSlides` / `orderedElements` / `orderedEntries` computed sorts and the `kind` enum accessor. Uses a real on-disk `ModelConfiguration(schema:url:)` for the reopen test.

## What it does NOT cover
It does not test the *app's* autosave behavior in a running process (that's `Persistence.makeContainer`'s autosaving main context, exercised by actually running the app), nor crash recovery under a real crash. It proves the data *can* round-trip through the store; the "autosave-so-nothing-is-lost" promise is verified by use and the dress rehearsal, not by this file.

## XCTest → Jest glossary
- `final class X: XCTestCase { }` — shape: subclass = test suite. Jest: `describe("X", () => { … })`.
- `func testFoo() throws` — shape: `test`-prefixed, may throw → can fail. Jest: `it("foo", () => { … })`.
- `@MainActor` — shape: main-thread run (for `ModelContext`). Jest: `// runs on the main thread`.
- `XCTAssertEqual(a, b)` — Jest: `expect(a).toEqual(b)`.
- `XCTUnwrap(x)` — shape: assert non-nil **and** return the value. Jest: `expect(x).toBeDefined(); const v = x!;`.
- `addTeardownBlock { … }` — shape: register post-test cleanup. Jest: `afterEach(() => …)`.
- `do { … }` — shape: a bare scope block (not try/catch) to bound lifetimes. Jest: a `{ … }` / IIFE used to drop references.
- `try` / `try?` — shape: prefix a throwing call / make it optional (`nil` on error). Jest: `await` / a `try/catch` swallow.
- `ModelContainer` / `ModelContext` / `ModelConfiguration` — shape: the store / the working session over it / its configuration (on-disk or in-memory). Jest analog: a DB connection / a unit-of-work session / connection options.
- `FetchDescriptor<T>()` / `fetchCount` — shape: typed "fetch all `T`" / "count `T`" query. Jest analog: `prisma.t.findMany()` / `prisma.t.count()`.
- `?.` (optional chaining) — Jest: `?.`.
- `enum`-backed field (`kind`, compared to `.song`) — shape: stored as a raw string with a computed accessor. Jest analog: a `"song"` string field.
