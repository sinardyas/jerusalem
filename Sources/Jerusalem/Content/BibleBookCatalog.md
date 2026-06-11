# `BibleBookCatalog.swift`

> The canonical list of all 66 Bible books, with an alias table that resolves messy user input ("1cor", "gen.", "PSALM") to a clean canonical name.

**Location:** `Sources/Jerusalem/Content/BibleBookCatalog.swift`
**Role:** catalog/data (pure namespace)

## What it does (plain English)

When an operator types a scripture reference like `1cor 13` or `psalm 23`, *something* has to decide that "1cor" really means "1 Corinthians" and "psalm" means "Psalms". That something is this file. It is the single source of truth for book names in the app.

It holds two things: an ordered list of the 66 canonical book names (`canonicalBooks`), and a lookup table (`aliases`) that maps every spelling variant we tolerate — full names, dotted/undotted abbreviations, no-space digit-prefixed forms — back to the one canonical name. The public entry point is `canonical(for:)`, which normalizes whatever the user typed and looks it up, returning `nil` if it's not a real book.

It sits at the very front of the Bible pipeline. The `BibleReferenceParser` calls into it to validate the book portion of a reference before it bothers parsing chapters and verses.

Being a caseless `enum` (a namespace, not a thing you instantiate), it has no model or UI dependencies, so it's trivially unit-testable.

## Swift you'll meet in this file

| Swift | JS/TS equivalent |
|---|---|
| `enum BibleBookCatalog { static func ... }` | `export const BibleBookCatalog = { ... }` — a namespace of pure functions/values, never instantiated |
| `static let canonicalBooks: [String]` | a module-level `const canonicalBooks: string[]` |
| `String?` (return of `canonical`) | `string \| null` |
| `[String: String]` | `Record<string, string>` / a `Map` |
| `.trimmingCharacters(in: .whitespacesAndNewlines)` | `str.trim()` |
| `.lowercased()` | `str.toLowerCase()` |
| `.components(separatedBy: .whitespaces)` | `str.split(/\s+/)` (roughly) |
| `.filter { !$0.isEmpty }` | `.filter(s => s.length > 0)`; `$0` is the implicit first arg, like an arrow param |
| `.joined(separator: " ")` | `arr.join(" ")` |
| `.replacingOccurrences(of: " ", with: "")` | `str.replaceAll(" ", "")` |
| `inout map` | passing an object by reference so the function can mutate it |
| `let aliases: [...] = { ... }()` | an IIFE: `const aliases = (() => { ... })()` |

## Code walkthrough

**The canonical list.** Just an ordered array of the 66 names. The string is also the display form the whole app uses — `"1 Corinthians"`, never `"1Cor"`.

```swift
static let canonicalBooks: [String] = [
    "Genesis", "Exodus", ... "Jude", "Revelation",
]
```

**The public lookup.** Normalize the input, then index into the alias table:

```swift
static func canonical(for input: String) -> String? {
    let key = normalize(input)
    return aliases[key]
}
```

`aliases[key]` returns `nil` automatically if the key isn't present — exactly the "unknown book" signal callers want.

**Normalizing.** Trim, lowercase, split on whitespace, drop empties, rejoin with a single space — so `"  1   Corinthians "` becomes `"1 corinthians"`:

```swift
let collapsed = input
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .lowercased()
    .components(separatedBy: .whitespaces)
    .filter { !$0.isEmpty }
    .joined(separator: " ")
```

**Building the alias table.** This is the clever part. The table is built once, lazily, via an IIFE-style closure assigned to a `static let`. A local helper `add(_:_:)` registers the canonical name plus its extra aliases:

```swift
add("1 Corinthians", ["1 cor", "1cor", "1 co", "1co"])
```

Each alias is fed to `register`, which inserts **three** forms into the map so they all resolve:

```swift
map[collapsed] = canonical                 // "1 cor"
let noSpace = collapsed.replacingOccurrences(of: " ", with: "")
if noSpace != collapsed { map[noSpace] = canonical }   // "1cor"
if collapsed.hasSuffix(".") {              // "gen." -> also "gen"
    map[String(collapsed.dropLast())] = canonical
}
```

**Worked example: `canonical(for: "1cor")`**
1. `normalize("1cor")` → `"1cor"` (already trimmed/lowercased, no spaces to collapse).
2. `aliases["1cor"]` → `"1 Corinthians"` because `register` indexed the no-space form when `add("1 Corinthians", [..., "1cor", ...])` ran.

**Worked example: `canonical(for: "Psalm")`**
1. `normalize("Psalm")` → `"psalm"`.
2. `aliases["psalm"]` → `"Psalms"` because `add("Psalms", ["psalm", "ps", ...])` registered it.

## How it connects

```
user text ──▶ BibleBookCatalog.canonical(for:)  ◀── (validates the book name)
                       ▲
                       │
              BibleReferenceParser.parse  ──▶ BibleStore ──▶ SlideSplitter ──▶ ContentRebuilder ──▶ Slides
```

It's the upstream-most piece of the Bible flow. Nothing depends on it except the parser (and any UI that wants to validate or list book names). It produces no slides directly — it just hands back a clean canonical book name or `nil`.

## Gotchas / why it matters

- **Single source of truth for book names.** Every part of the app that shows or matches a book name funnels through this canonical string, so labels read consistently ("1 Corinthians", never "1Cor").
- **Generous on input, strict on output.** It accepts case/whitespace/abbreviation variants but always returns the *one* canonical form (or `nil`). That `nil` is how the editor surfaces a clean "unknown book" state instead of guessing.
- **Pure and testable.** No SwiftData, no AppKit — just strings in, strings out. The alias map is built once at first access (O(1) lookups thereafter).
