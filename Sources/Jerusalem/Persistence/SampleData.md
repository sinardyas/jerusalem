# `SampleData.swift`

> Seeds a single sample song ("Amazing Grace") and a playlist into an empty store on first launch, so the app opens with something to look at.

**Location:** `Sources/Jerusalem/Persistence/SampleData.swift`
**Role:** data seeder (namespace of pure functions)

## What it does (plain English)

On a brand-new (empty) database, this inserts one song item, gives it a default theme and some lyrics, and drops it into a playlist. After that, a fresh install isn't a blank screen during development.

It runs **only when the store is empty** — it counts existing `Item` rows first and bails out if there are any. That makes it idempotent: it won't keep adding "Amazing Grace" every launch, and it won't fight with content a real user has created.

Notably (Phase 6), it doesn't hand-build slides. It writes the lyrics as text plus `SongSection` rows and lets `ContentRebuilder` derive the actual slides — the exact same pipeline the in-app editor uses. So the sample data flows through the real content path, not a special-case one.

## Swift you'll meet in this file

| Swift | JS/TS analogy |
|---|---|
| `enum SampleData { static ... }` | Caseless `enum` as a **namespace** of pure functions (shape: `enum Foo { static func }`) — `export const SampleData = { ... }`. |
| `@MainActor` | Must run on the main (UI) thread. Shape: `@MainActor func`. |
| `ModelContext` | A SwiftData session — like a Prisma transaction; `insert` adds rows, `save` flushes. |
| `try? context.fetchCount(...) ?? 0` | Run a throwing query; on error use `nil`, then `?? 0` falls back to `0`. |
| `FetchDescriptor<Item>()` | A query object (here, "all `Item`s"). Shape: `FetchDescriptor<Entity>()`. |
| `guard existing == 0 else { return }` | Early-return: "unless empty, stop." Shape: `guard cond else { return }`. |
| `let song = Item(...)` | Create an instance. `Item` is a `@Model` class (reference type, shared like a JS object). |
| `song.theme = ...` / `song.linesPerSlide = 2` | Mutating object properties. |
| `kind: .song` | Leading-dot shorthand for an enum case (`Kind.song`) when the type is inferred. |
| `"""..."""` | A multi-line string literal — like a JS template literal/backticks. |
| `[entry]` | An array literal — `[entry]` in TS too. |

## Code walkthrough

### The empty-store guard

```swift
@MainActor
static func seedIfNeeded(_ context: ModelContext) {
    let existing = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
    guard existing == 0 else { return }
```

**TypeScript equivalent**

```ts
// analogy: @MainActor ≈ UI thread; context ≈ a Prisma-like session.
function seedIfNeeded(context: ModelContext): void {
  let existing: number;
  try { existing = context.fetchCount({ entity: Item }); } catch { existing = 0; }  // try? ... ?? 0
  if (existing !== 0) return;   // guard existing == 0 else { return }
  // ...continues below
}
```

Count all `Item` rows. `try?` turns a thrown error into `nil`, and `?? 0` defaults that to `0`. If there's already at least one item, `guard ... else { return }` exits — this is the idempotency check.

**Swift syntax:**
- `static func seedIfNeeded(_ context:)` — `static` namespace function; `_` drops the argument label so callers write `seedIfNeeded(ctx)`.
- `(try? context.fetchCount(FetchDescriptor<Item>())) ?? 0` — `try?` makes a throwing call yield `nil` on error; `?? 0` then supplies a default. `FetchDescriptor<Item>()` with no predicate means "all `Item` rows." TS: `try { ... } catch { = 0 }`.
- `guard existing == 0 else { return }` — invert-and-bail: continue only if the store is empty, else return. TS: `if (existing !== 0) return;`.

### Building the song

```swift
let song = Item(kind: .song, title: "Amazing Grace", subtitle: "John Newton")
song.theme = Theme.makeDefault()
song.linesPerSlide = 2
context.insert(song)
```

**TypeScript equivalent**

```ts
const song = new Item({ kind: Kind.song, title: "Amazing Grace", subtitle: "John Newton" });
song.theme = Theme.makeDefault();
song.linesPerSlide = 2;
context.insert(song);
```

Create an `Item` of kind `.song` (a shared reference object), set its default `Theme` and how many lyric lines go per slide, then `insert` it into the session. `kind: .song` uses Swift's shorthand for an enum case (the type is inferred), like passing a known constant.

**Swift syntax:**
- `let song = Item(...)` — `let` binds a constant *reference*. `Item` is a `@Model` **class** (reference type), so even though `song` is `let`, you can still mutate its properties (`song.theme = ...`) — `let` freezes the binding, not the object. (For a `struct`, `let` would freeze the value too.)
- `kind: .song` — **leading-dot syntax**: `.song` is shorthand for `Kind.song`, allowed because the parameter's type is already known. Like referencing an enum member without repeating the enum name.
- `context.insert(song)` — stages the new object in the session (tracked for saving). Like `prisma`-style `create`, but persisted on the next save.

### The lyrics

```swift
let lyrics = """
[Verse 1]
Amazing grace! How sweet the sound
...
[Chorus]
My chains are gone, I’ve been set free
My God, my Savior has ransomed me
"""
ContentRebuilder.setLyrics(lyrics, on: song)
```

**TypeScript equivalent**

```ts
const lyrics = `[Verse 1]
Amazing grace! How sweet the sound
...
[Chorus]
My chains are gone, I’ve been set free
My God, my Savior has ransomed me`;
ContentRebuilder.setLyrics(lyrics, song);   // analogy: runs the real content pipeline
```

A multi-line string (triple-quoted, like backticks in JS) holds the lyrics with `[Verse 1]` / `[Chorus]` section markers. `ContentRebuilder.setLyrics` parses those markers into `SongSection` rows and derives the slides — the same code path the real editor uses, so the seed isn't a special case.

**Swift syntax:**
- `""" ... """` — a **multi-line string literal**. The opening/closing `"""` sit on their own lines and the closing delimiter's indentation is stripped from each line. Equivalent to a JS template literal (backticks) — but without `${}` interpolation here.
- `ContentRebuilder.setLyrics(lyrics, on: song)` — `on:` is an argument label that reads like a preposition (Swift API style). Same as `setLyrics(lyrics, song)` in TS.

### The playlist

```swift
let playlist = Playlist(name: "Sunday AM · May 31")
let entry = PlaylistEntry(order: 0)
entry.item = song
playlist.entries = [entry]
context.insert(playlist)

try? context.save()
```

**TypeScript equivalent**

```ts
const playlist = new Playlist({ name: "Sunday AM · May 31" });
const entry = new PlaylistEntry({ order: 0 });
entry.item = song;             // join row points at the song
playlist.entries = [entry];
context.insert(playlist);

try { context.save(); } catch { /* try? swallows the error */ }
```

A `Playlist` doesn't link to items directly — it goes through a `PlaylistEntry` join row (so one item can appear in many playlists with per-playlist ordering). Here one entry at `order: 0` points to the song, the playlist gets that single entry, the playlist is inserted, and `try? context.save()` flushes everything to disk (ignoring any error).

**Swift syntax:**
- `playlist.entries = [entry]` — assign an **array literal** to the relationship property. `[entry]` is a one-element array (`[entry]` in TS too).
- `entry.item = song` — sets a to-one relationship by reference; SwiftData tracks both sides.
- `try? context.save()` — flush staged inserts to disk, discarding any thrown error. Inserting `playlist` cascades to its `entries` because they're related.

## How it connects

- **`Persistence.makeContainer`** calls `SampleData.seedIfNeeded(context)` right after the container is built (alongside `BibleSeeder`).
- **`Item`, `Theme`, `Playlist`, `PlaylistEntry`, `SongSection`** are the `@Model` types it creates/relates.
- **`ContentRebuilder.setLyrics`** is the shared content pipeline that turns the raw lyrics + sections into slides — the seed routes through it instead of building slides by hand.

## Gotchas / why it matters

- **Idempotent via emptiness.** It only seeds when there are zero `Item`s, so it never duplicates the sample and never overwrites real user content.
- **Uses the real content pipeline.** By calling `ContentRebuilder.setLyrics` rather than fabricating `Slide` rows, the sample exercises the same derivation logic as the editor — fewer surprises and one less special case to maintain.
- **Join-model relationship.** Playlists link to items through `PlaylistEntry`, not directly. If you add seed content, follow that pattern.
