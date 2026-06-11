# `Persistence.swift`

> Central SwiftData setup: declares the schema and builds the shared, autosaving, on-disk database container the whole app uses.

**Location:** `Sources/Jerusalem/Persistence/Persistence.swift`
**Role:** SwiftData setup namespace (pure static helpers)

## What it does (plain English)

This is the single place that wires up the app's database. SwiftData is Apple's persistence framework; think of a `ModelContainer` as the database connection and a `ModelContext` as a working session/transaction on top of it.

Two things live here:

1. **`schema`** — the list of "root" model types the database knows about. You only list the roots; SwiftData walks their relationships to discover the rest automatically (so `Slide`, `SlideElement`, etc. are reachable from `Item`).

2. **`makeContainer`** — builds the actual container (on disk by default, or in-memory for tests), then immediately runs the seeders so a fresh install has Bible verses and a sample song to show.

The container's main context **autosaves by default**, meaning edits are flushed to disk without you calling `save()` everywhere. That autosave behavior is the foundation of the app's crash-recovery promise ("never fail on Sunday morning") — if the app dies, recent edits were already written.

## Swift you'll meet in this file

| Swift | JS/TS analogy |
|---|---|
| `enum Persistence { static let ...; static func ... }` | Caseless enum as a **namespace** of stateless helpers — `export const Persistence = { ... }`. |
| `static let schema = Schema([...])` | A constant (`const`) holding the model registry. |
| `Item.self` | A reference to the *type itself* (not an instance) — like passing the class `Item` rather than `new Item()`. |
| `ModelContainer` / `ModelContext` (SwiftData) | The DB connection + a unit-of-work session — like a Prisma client + a transaction. |
| `ModelConfiguration(... isStoredInMemoryOnly:)` | Config object; the flag chooses in-memory vs on-disk storage (in-memory is great for tests). |
| `@MainActor` | This function must run on the main (UI) thread. |
| `inMemory: Bool = false` | A parameter with a **default value** — like `inMemory = false` in JS. |
| `do { ... try ... } catch { ... }` | `try/catch`. `try` marks a call that can throw. |
| `fatalError(...)` | Deliberately crash with a message — like `throw` you never intend to recover from. |
| `\(error)` | String interpolation — like `` `${error}` ``. |

## Code walkthrough

### The schema

```swift
static let schema = Schema([
    Item.self,
    Slide.self,
    SlideElement.self,
    SongSection.self,
    BibleVerse.self,
    Theme.self,
    Playlist.self,
    PlaylistEntry.self,
])
```

A `Schema` is the registry of `@Model` entity types. Each `X.self` passes the *type* (not an instance). The comment notes you only need the roots — SwiftData finds related models through relationships — but here they're listed explicitly for clarity.

### Building the container

```swift
@MainActor
static func makeContainer(inMemory: Bool = false) -> ModelContainer {
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
    do {
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        BibleSeeder.seedIfNeeded(context)   // Phase 7: bundled scripture
        SampleData.seedIfNeeded(context)
        return container
    } catch {
        fatalError("Could not create the Jerusalem model container: \(error)")
    }
}
```

Step by step, in JS terms:

- Build a config; `inMemory` defaults to `false` (real on-disk DB), but tests pass `true` for an ephemeral store.
- `try ModelContainer(...)` opens the database — this can throw, so it's inside `do/catch`.
- Create a `ModelContext` (a session) and hand it to the two seeders. Both are **idempotent** — they only insert when the relevant data is missing — so calling them on every launch is safe.
- Return the container for the app to inject.
- If construction fails, `fatalError` crashes immediately with a descriptive message. The reasoning: an app with no database is unusable, so there's nothing graceful to do — fail loud, fail early.

`@MainActor` is required because seeding flows through `ContentRebuilder`, which mutates SwiftData models that the renderer reads on the main thread.

## How it connects

- **`JerusalemApp`** calls `Persistence.makeContainer()` once and injects the result via `.modelContainer(container)` into both window groups.
- **`BibleSeeder.seedIfNeeded`** and **`SampleData.seedIfNeeded`** are invoked here, right after the container is built.
- **`schema`** references every `@Model` root: `Item`, `Slide`, `SlideElement`, `SongSection`, `BibleVerse`, `Theme`, `Playlist`, `PlaylistEntry`.

## Gotchas / why it matters

- **Autosave is the crash-recovery foundation.** The main context autosaves by default. Avoid patterns that defeat that — it's what protects in-progress edits if the app dies.
- **In-memory mode is for tests.** Pass `inMemory: true` to get a disposable store; the default on-disk container is what ships.
- **`fatalError` is intentional.** No database means no app, so it crashes rather than limping along in a broken state.
- **Seeders run every launch but only act when needed.** Their idempotency lives in the seeders themselves, not here — `makeContainer` just calls them unconditionally.
