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
| `enum BibleSeeder { static func ... }` | Caseless `enum` used as a **namespace** of pure functions (shape: `enum Foo { static func bar() }`) — like `export const BibleSeeder = { bar() {} }`. No instances are ever created. |
| `@MainActor` | An annotation forcing the function to run on the main thread (UI thread). Shape: `@MainActor func/var`. Think "must run on the main loop." |
| `static func seedIfNeeded(_ context: ModelContext)` | A static method. `_` before `context` means the call site omits the label: `seedIfNeeded(ctx)`. `ModelContext` is a SwiftData session — like a Prisma transaction / unit-of-work. |
| `guard let x = ... else { return }` | An early-return null check that **binds** `x` for the rest of the function. Shape: `guard let x = maybe else { return }`. Like `if (!x) return;` but `x` is now non-null below. |
| `T?` and `?.` and `?? []` | `T \| null`; optional chaining (`a?.b`); `?? []` is nullish-coalescing (`a ?? []`) to a default empty array. |
| `try?` | Run something that can throw; on error, produce `nil` instead of throwing. Shape: `try? doThing()`. Like wrapping in `try/catch` and returning `null` on failure. |
| `struct Foo: Decodable` | A value type (copied, not shared) that can be parsed from JSON. Shape: `struct Name: Protocol {}` — like a TS type used with `JSON.parse`, but the decoding is type-checked. |
| `[T]` | An array of `T` — `T[]` in TS. |
| `$0` | The first (implicit) closure argument, like an arrow function's first param: `x => ...`. |
| `Hashable, Identifiable, Sendable` | Protocols (interfaces) after the `:`. `Identifiable` means "has an `id`" (used by SwiftUI lists); `Sendable` means "safe to pass across threads." |

## Code walkthrough

The whole file is a namespace — no objects are instantiated:

```swift
enum BibleSeeder {
```

**TypeScript equivalent**

```ts
// analogy: a module namespace object holding only static helpers — never instantiated.
export const BibleSeeder = {
  // ...static functions live here
};
```

**Swift syntax:**
- `enum BibleSeeder { static func ... }` — a *caseless* enum used purely as a **namespace**. Because it has no cases you can't make an instance of it; you only call its `static` members. Maps to an exported object literal of functions in TS (`export const BibleSeeder = { ... }`).

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

**TypeScript equivalent**

```ts
// analogy: @MainActor ≈ must run on the UI thread; context ≈ a Prisma-like DB session.
function seedIfNeeded(context: ModelContext): void {
  const starter = loadStarter();
  if (!starter) return;                       // guard let ... else { return }
  for (const translation of starter.translations) {
    const key = translation.id.toLowerCase();
    if (BibleStore.isSeeded(key, context)) continue;
    for (const verse of translation.verses) {
      context.insert(new BibleVerse({
        translation: key,
        book: verse.book,
        chapter: verse.chapter,
        number: verse.number,
        text: verse.text,
      }));
    }
  }
  try { context.save(); } catch { /* try? swallows the error */ }
}
```

In JS terms: load the JSON; if it failed, bail out. For each translation, lowercase its id as a stable `key`. If that translation is **already in the DB** (`isSeeded`), skip it (`continue`). Otherwise insert every verse as a `BibleVerse` row into the SwiftData session (`context.insert`), then `try? context.save()` writes it to disk (ignoring any error). The `isSeeded` check is what makes a second run a no-op.

**Swift syntax:**
- `@MainActor` — pins this function to the main (UI) thread; the compiler enforces callers also run there. No direct TS equivalent — think "must be on the event loop / UI thread."
- `static func seedIfNeeded(_ context:)` — `static` = belongs to the type, not an instance (a module function). The `_` suppresses the argument label so callers write `seedIfNeeded(ctx)` not `seedIfNeeded(context: ctx)`.
- `guard let starter = loadStarter() else { return }` — unwrap-or-bail: if `loadStarter()` is `nil`, return; otherwise `starter` is non-optional for the rest of the scope. TS: `const starter = loadStarter(); if (!starter) return;`.
- `for x in seq { }` — for-of loop. `continue` skips to the next iteration, same as JS.
- labeled call args `BibleVerse(translation: key, book: ...)` — Swift initializers use named arguments; reads like an object literal passed to a constructor.
- `try? context.save()` — call a throwing function but turn a thrown error into a discarded `nil`. TS: `try { ... } catch {}`.

### `bundledTranslations`

```swift
static func bundledTranslations() -> [BundledTranslation] {
    loadStarter()?.translations.map {
        BundledTranslation(id: $0.id.lowercased(), displayName: $0.displayName)
    } ?? []
}
```

**TypeScript equivalent**

```ts
function bundledTranslations(): BundledTranslation[] {
  return (loadStarter()?.translations.map(
    (t) => ({ id: t.id.toLowerCase(), displayName: t.displayName })
  )) ?? [];
}
```

Loads the JSON, maps each translation block to a lightweight `BundledTranslation` value, and returns `[]` if loading failed (`?? []`). This is purely for the editor's picker, so the UI list stays "in lockstep" with shipped data.

**Swift syntax:**
- `-> [BundledTranslation]` — return type "array of `BundledTranslation`" (`BundledTranslation[]`).
- single-expression function — a function whose whole body is one expression has an implicit `return` (no `return` keyword needed).
- `loadStarter()?.translations` — optional chaining: if `loadStarter()` is `nil`, the whole chain short-circuits to `nil`.
- `.map { ... }` with trailing closure — `.map(...)` whose closure is written *after* the call in `{ }`. `$0` is the closure's first (implicit) argument, i.e. each translation. TS: `.map((t) => ...)`.
- `?? []` — nullish-coalescing default.

### `BundledTranslation`

```swift
struct BundledTranslation: Hashable, Identifiable, Sendable {
    var id: String
    var displayName: String
}
```

**TypeScript equivalent**

```ts
// analogy: a plain value object surfaced to the UI; Identifiable ≈ "has an id" for list keys.
interface BundledTranslation {
  id: string;          // Identifiable
  displayName: string;
}
```

A tiny value type (like a TS interface `{ id: string; displayName: string }`) surfaced to the UI. `Identifiable` lets SwiftUI use it directly in lists.

**Swift syntax:**
- `struct ... { var ... }` — a **value type**: assigning or passing it copies it (unlike a `class`, which is shared by reference). The conformances after `:` (`Hashable, Identifiable, Sendable`) are protocols/interfaces it satisfies.

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

**TypeScript equivalent**

```ts
// analogy: TS interfaces describing the shape of bible-starter.json, parsed type-safely.
interface Starter { translations: TranslationBlock[]; }
interface TranslationBlock { id: string; displayName: string; verses: VerseRecord[]; }
interface VerseRecord { book: string; chapter: number; number: number; text: string; }
```

These four `Decodable` structs are the **typed schema of `bible-starter.json`** — the equivalent of writing TypeScript interfaces for a JSON file so parsing is type-checked. `private` means they're internal to this file.

**Swift syntax:**
- `private struct` — `private` scopes the type to this file (here, file-private helper shapes). TS has no exact file-scope equivalent; think "not exported."
- `Decodable` — a protocol that lets `JSONDecoder` build the value from JSON automatically (the compiler synthesizes the parsing from the property names). Like a runtime-checked version of casting `JSON.parse` to an interface.
- `Int` — Swift's integer type, maps to `number` in TS.

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

**TypeScript equivalent**

```ts
// analogy: Bundle ≈ the packaged app's resource folder; reading a bundled asset off disk.
function loadStarter(): Starter | null {
  const candidates: Bundle[] = [Bundle.for(BibleVerse), Bundle.main];
  for (const bundle of candidates) {
    const url = bundle.url("bible-starter", "json");          // may be null
    if (!url) continue;
    let data: Buffer;
    try { data = fs.readFileSync(url); } catch { continue; }   // try?
    try {
      return JSON.parse(data.toString()) as Starter;           // try? decode
    } catch { continue; }
  }
  return null;
}
```

A "bundle" is the packaged app's resource folder (where shipped files live). It tries two locations: the bundle that ships the Jerusalem module (`Bundle(for: BibleVerse.self)`) and the main app bundle (`.main`). For each, it chains three optional-binding steps — find the file URL, read the bytes, decode the JSON — and any failure cleanly falls through to the next candidate, returning `nil` if both fail. The dual-bundle trick matters because tests `@testable import` the module and need the resource found too.

**Swift syntax:**
- `-> Starter?` — returns an **optional** `Starter` (`Starter | null`); `nil` signals "couldn't load."
- `let candidates: [Bundle] = [...]` — an explicitly-typed array literal. `.main` is shorthand for `Bundle.main` (Swift infers the leading type, like writing `Bundle.main` without the prefix).
- `Bundle(for: BibleVerse.self)` — `BibleVerse.self` is the *type itself* (the metatype), not an instance — like passing the class `BibleVerse` rather than `new BibleVerse()`. Resolves the bundle that ships that type.
- chained `if let a = ..., let b = ..., let c = ... { }` — multiple optional bindings joined by commas act as **AND**: all must be non-nil for the body to run; any `nil` skips it. TS needs manual `if (!a) continue;` steps.
- `bundle.url(forResource:withExtension:)` — locates a bundled resource file by name+extension, returning a URL or `nil`. Like resolving a path to a packaged asset.
- `Data(contentsOf: url)` — reads the file's raw bytes (can throw → wrapped in `try?`). Like `fs.readFileSync`.
- `JSONDecoder().decode(Starter.self, from: data)` — parses JSON bytes into a `Starter`, type-checked against the `Decodable` shape. Like `JSON.parse(...) as Starter` but validated.

## How it connects

- **`Persistence.makeContainer`** calls `BibleSeeder.seedIfNeeded(context)` right after building the container (see `Persistence.swift`).
- **`BibleStore`** provides `isSeeded(translation:in:)` (the skip check) and is the offline reader these rows feed.
- **`BibleVerse`** (a SwiftData `@Model`) is the row type being inserted; it's also used to locate the resource bundle.
- **`bible-starter.json`** is the bundled data file this code reads.

## Gotchas / why it matters

- **Idempotent by design.** The per-translation `isSeeded` check is what lets the app call this on every launch without duplicating verses. Don't remove that guard.
- **Stable lowercased keys.** Translation ids are lowercased before storing and comparing, so casing in the JSON doesn't create duplicate translations.
- **Bundle resolution matters for tests.** The two-candidate `loadStarter` is not redundant — it's what lets headless XCTest find the JSON when it `@testable import`s the module.
