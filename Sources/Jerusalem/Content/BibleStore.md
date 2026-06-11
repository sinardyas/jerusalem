# `BibleStore.swift`

> The read-only query layer over the offline `BibleVerse` rows: given a parsed reference and a translation, it fetches the matching verses from SwiftData.

**Location:** `Sources/Jerusalem/Content/BibleStore.swift`
**Role:** DB store (read-side, `@MainActor` namespace)

## What it does (plain English)

The whole Bible ships *inside the app* as `BibleVerse` rows in the local SwiftData database (offline — no network, ever, because it must not fail on a Sunday with bad Wi-Fi). This file is how the rest of the app reads those rows.

It exposes two pure static functions. `verses(for:translation:in:)` takes a `BibleReference` (already parsed) plus a translation key like `"kjv"`, runs a typed query against the database context, and returns the matching verses sorted by verse number. `isSeeded(translation:in:)` is a cheap "have we loaded this translation yet?" check used by the seeder at startup.

There is no write side here — scripture is read-only after the initial seed. The store sits between the parser (which gives it a structured reference) and the splitter (which turns the returned verses into slides).

## Swift you'll meet in this file

| Swift | JS/TS equivalent |
|---|---|
| `@MainActor enum BibleStore` | a namespace pinned to the main thread (so all DB access stays single-threaded by the project's rules) |
| `ModelContext` | a SwiftData DB session — your handle for queries (like a Prisma client / DB connection) |
| `FetchDescriptor<BibleVerse>` | a typed query object: *what* table + *which* rows + *how* to sort |
| `#Predicate { verse in ... }` | the `WHERE` clause, written as a closure; `&&` is logical AND |
| `SortDescriptor(\.number)` | `ORDER BY number ASC`; `\.number` is a key-path (like `v => v.number`) |
| `try? context.fetch(descriptor)` | run the query; `try?` turns a thrown error into `nil` |
| `(try? ...) ?? []` | run query, and if it returned `nil`, fall back to `[]` (nullish coalescing) |
| `descriptor.fetchLimit = 1` | `LIMIT 1` |
| `context.fetchCount(...)` | `SELECT COUNT(*)` without materializing rows |
| `translation.lowercased()` | normalize the key, `str.toLowerCase()` |

## Code walkthrough

**Two query shapes.** The function branches on whether the reference has a verse range. With a range, it adds `number >= low && number <= high` to the predicate:

```swift
if let range = reference.verses {
    let low = range.lowerBound
    let high = range.upperBound
    let descriptor = FetchDescriptor<BibleVerse>(
        predicate: #Predicate { verse in
            verse.translation == translationKey
            && verse.book == book
            && verse.chapter == chapter
            && verse.number >= low
            && verse.number <= high
        },
        sortBy: [SortDescriptor(\.number)])
    return (try? context.fetch(descriptor)) ?? []
}
```

Note the local `let low`/`let high` and `let book`/`let chapter` bindings: the `#Predicate` macro can only capture simple local values, so the fields are pulled out of `reference` first.

Without a range (whole chapter), the predicate drops the `number` bounds and matches every verse in the chapter:

```swift
let descriptor = FetchDescriptor<BibleVerse>(
    predicate: #Predicate { verse in
        verse.translation == translationKey
        && verse.book == book
        && verse.chapter == chapter
    },
    sortBy: [SortDescriptor(\.number)])
return (try? context.fetch(descriptor)) ?? []
```

Both branches sort by `number` and use `(try? ...) ?? []`, so a query failure or a not-yet-seeded translation simply yields an empty array — the caller treats "empty" as "unknown reference."

**The seeded check.** A count query capped at 1 — the cheapest possible "does any row exist for this translation?":

```swift
var descriptor = FetchDescriptor<BibleVerse>(
    predicate: #Predicate { $0.translation == translationKey })
descriptor.fetchLimit = 1
return ((try? context.fetchCount(descriptor)) ?? 0) > 0
```

`$0` is the implicit verse argument. `fetchLimit = 1` means it stops as soon as it finds one row.

## How it connects

```
BibleReferenceParser.parse ──▶ BibleReference
                                    │
                                    ▼
              BibleStore.verses(for:translation:in:)  ──▶ [BibleVerse]
                                    │
                                    ▼
                       SlideSplitter.split(bibleVerses:) ──▶ [SlideDraft]
                                    │
                                    ▼
                          ContentRebuilder.materialize ──▶ Slides
```

`ContentRebuilder.rebuildBible` is the caller: it parses the reference, calls `BibleStore.verses(...)`, and feeds the result to the splitter. Separately, `BibleSeeder` (out of this file) calls `isSeeded` at startup to decide whether to load the bundled starter dataset.

## Gotchas / why it matters

- **Read-only, offline.** No writes here — verses are immutable after seeding. The entire Bible lives in the local SwiftData store, so lookups never touch the network. That's the "never fail on Sunday morning" promise applied to scripture.
- **Empty array = unknown/not seeded.** Both the failure path and a genuinely missing reference return `[]`. The editor reads that as the unknown-reference state; the splitter reads it as "no slides."
- **`@MainActor` on purpose.** SwiftData access in this app is main-thread-only. Pinning the namespace to `@MainActor` means callers don't have to manage contexts/threads themselves.
- **Translation is lowercased** before querying (`translationKey`), matching how rows are stored — so `"KJV"` and `"kjv"` both work.
- **Predicate capture quirk.** `#Predicate` can't read `reference.verses.lowerBound` inline; the code copies fields into plain locals (`low`, `high`, `book`, `chapter`) first so the macro can capture them.
