# `BibleSeeder.swift`

> A one-shot loader that reads bundled Bible verses from JSON and inserts them into the SwiftData store so scripture can be looked up offline.

**Location:** `Sources/Jerusalem/Persistence/BibleSeeder.swift`
**Role:** data seeder (namespace of pure functions)

## What it does (plain English)

On the very first launch — or any time a particular translation is missing from the database — this file loads a bundled JSON file (`bible-starter.json`) and inserts each verse as a `BibleVerse` row. Once those rows exist, the rest of the app (`BibleStore`) can serve verses without any network access.

The shipped dataset is deliberately small (John 3, Psalm 23, Rom 8:28, Phil 4:13 in two translations, KJV + WEB) — just enough to pass the "Phase 7" milestone. You can swap in a much larger JSON file later and the seeder won't care; it just reads whatever is in the bundle.

The key promise here is **idempotency**: running the seeder twice does nothing the second time. It checks per-translation whether the data is already loaded before inserting, so you can safely call it on every launch.

It also exposes a small helper, `bundledTranslations()`, so the UI's translation picker only ever lists translations the app actually has data for.

## Swift you'll meet in this file

| Swift | JS/TS analogy |
|---|---|
| `enum BibleSeeder { static func ... }` | A caseless enum used as a **namespace** of pure functions — like `export const BibleSeeder = { ... }`. No instances are ever created. |
| `@MainActor` | An annotation forcing the function to run on the main thread (UI thread). Think "must run on the main loop." |
| `static func seedIfNeeded(_ context: ModelContext)` | A static method. `ModelContext` is a SwiftData session — like a Prisma transaction / unit-of-work. |
| `guard let x = ... else { return }` | An early-return null check that **binds** `x` for the rest of the function. Like `if (!x) return;` but `x` is now non-null below. |
| `T?` and `?.` and `?? []` | `T \| null`; optional chaining; `?? []` is nullish-coalescing to a default empty array. |
| `try?` | Run something that can throw; on error, produce `nil` instead of throwing. Like wrapping in `try/catch` and returning `null` on failure. |
| `struct Foo: Decodable` | A value type (copied, not shared) that can be parsed from JSON — like a TS type used with `JSON.parse`, but the decoding is type-checked. |
| `[T]` | An array of `T`. |
| `$0` | The first (implicit) closure argument, like an arrow function's first param. |
| `Hashable, Identifiable, Sendable` | Protocols (interfaces). `Identifiable` means "has an `id"` (used by SwiftUI lists); `Sendable` means "safe to pass across threads." |

## Code walkthrough

The whole file is a namespace — no objects are instantiated:

```swift
enum BibleSeeder {
```

### `seedIfNeeded`

```swift
@MainActor
static func seedIfNeeded(_ context: ModelContext) {
    guard let starter = loadStarter() else { return }
    for translation in starter.translations {
        let key = translation.id.lowercased()
        if BibleStore.isSeeded(translation: key, in: context) { continue }
        for verse in translation.verses {
            context.insert(BibleVerse(
                translation: key,
                book: verse.book,
                chapter: verse.chapter,
                number: verse.number,
                text: verse.text))
        }
    }
    try? context.save()
}
```

In JS terms: load the JSON; if it failed, bail out. For each translation, lowercase its id as a stable `key`. If that translation is **already in the DB** (`isSeeded`), skip it (`continue`). Otherwise insert every verse as a `BibleVerse` row into the SwiftData session (`context.insert`), then `try? context.save()` writes it to disk (ignoring any error). The `isSeeded` check is what makes a second run a no-op.

### `bundledTranslations`

```swift
static func bundledTranslations() -> [BundledTranslation] {
    loadStarter()?.translations.map {
        BundledTranslation(id: $0.id.lowercased(), displayName: $0.displayName)
    } ?? []
}
```

Loads the JSON, maps each translation block to a lightweight `BundledTranslation` value, and returns `[]` if loading failed (`?? []`). This is purely for the editor's picker, so the UI list stays "in lockstep" with shipped data.

### `BundledTranslation`

```swift
struct BundledTranslation: Hashable, Identifiable, Sendable {
    var id: String
    var displayName: String
}
```

A tiny value type (like a TS interface `{ id: string; displayName: string }`) surfaced to the UI. `Identifiable` lets SwiftUI use it directly in lists.

### Private JSON shapes

```swift
private struct Starter: Decodable {
    var translations: [TranslationBlock]
}
private struct TranslationBlock: Decodable {
    var id: String
    var displayName: String
    var verses: [VerseRecord]
}
private struct VerseRecord: Decodable {
    var book: String
    var chapter: Int
    var number: Int
    var text: String
}
```

These four `Decodable` structs are the **typed schema of `bible-starter.json`** — the equivalent of writing TypeScript interfaces for a JSON file so parsing is type-checked. `private` means they're internal to this file.

### `loadStarter`

```swift
private static func loadStarter() -> Starter? {
    let candidates: [Bundle] = [Bundle(for: BibleVerse.self), .main]
    for bundle in candidates {
        if let url = bundle.url(forResource: "bible-starter", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let starter = try? JSONDecoder().decode(Starter.self, from: data) {
            return starter
        }
    }
    return nil
}
```

A "bundle" is the packaged app's resource folder (where shipped files live). It tries two locations: the bundle that ships the Jerusalem module (`Bundle(for: BibleVerse.self)`) and the main app bundle (`.main`). For each, it chains three optional-binding steps — find the file URL, read the bytes, decode the JSON — and any failure cleanly falls through to the next candidate, returning `nil` if both fail. The dual-bundle trick matters because tests `@testable import` the module and need the resource found too.

## How it connects

- **`Persistence.makeContainer`** calls `BibleSeeder.seedIfNeeded(context)` right after building the container (see `Persistence.swift`).
- **`BibleStore`** provides `isSeeded(translation:in:)` (the skip check) and is the offline reader these rows feed.
- **`BibleVerse`** (a SwiftData `@Model`) is the row type being inserted; it's also used to locate the resource bundle.
- **`bible-starter.json`** is the bundled data file this code reads.

## Gotchas / why it matters

- **Idempotent by design.** The per-translation `isSeeded` check is what lets the app call this on every launch without duplicating verses. Don't remove that guard.
- **Stable lowercased keys.** Translation ids are lowercased before storing and comparing, so casing in the JSON doesn't create duplicate translations.
- **Bundle resolution matters for tests.** The two-candidate `loadStarter` is not redundant — it's what lets headless XCTest find the JSON when it `@testable import`s the module.
