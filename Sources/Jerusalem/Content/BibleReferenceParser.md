# `BibleReferenceParser.swift`

> Turns a free-typed string like `"John 3:16-18"` into a structured `BibleReference` value (book, chapter, verse range), or `nil` if it's malformed.

**Location:** `Sources/Jerusalem/Content/BibleReferenceParser.swift`
**Role:** pure parser/namespace (+ the `BibleReference` value type)

## What it does (plain English)

The operator types scripture references by hand — `John 3:16`, `Psalm 23`, `1 Corinthians 13:4-7`, even sloppy ones like `1cor 13`. This file converts that free text into a tidy struct the rest of the app can query against, and rejects nonsense by returning `nil`.

It defines two things. `BibleReference` is the parsed result: a value type holding `book`, `chapter`, and an optional verse range. `BibleReferenceParser` is the parser namespace whose `parse(_:)` function does the work — delegating book-name resolution to `BibleBookCatalog` and handling the chapter/verse numbers itself.

In the pipeline it sits right after the catalog and right before the store: parse the text → get a `BibleReference` → hand it to `BibleStore` to fetch actual verse rows.

## Swift you'll meet in this file

| Swift | JS/TS equivalent |
|---|---|
| `struct BibleReference: Equatable, Sendable` | a value-type record (copied, not shared); `Equatable` = has `==`; `Sendable` = safe to pass across threads |
| `var verses: ClosedRange<Int>?` | `verses: {lower:number, upper:number} \| null` — an inclusive range `16...18`, or null = "whole chapter" |
| `var displayText: String { ... }` | a computed getter (like a TS `get displayText()`) |
| `guard let verses else { return ... }` | `if (verses == null) return ...` — an early-exit null check |
| `"\(book) \(chapter)"` | template literal `` `${book} ${chapter}` `` |
| `enum BibleReferenceParser { static func parse(...) }` | `export const BibleReferenceParser = { parse() {...} }` |
| `input.split(whereSeparator: \.isWhitespace)` | `input.split(/\s+/)` — `\.isWhitespace` is a key-path predicate |
| `.map(String.init)` | `.map(x => String(x))` — convert each substring to a real `String` |
| `tokens.last!` | `tokens[tokens.length-1]` with a force-unwrap (crashes if empty — but guarded above) |
| `token.firstIndex(of: ":")` | `str.indexOf(":")`, returning a `String.Index` or `nil` |
| `Int(token[..<colon])` | `parseInt` that returns `null` instead of `NaN` on failure |
| `start...end` | builds the inclusive range value |

## Code walkthrough

**The result type.** `BibleReference` is a plain value record. Its `displayText` builds the human label used as a slide section header, branching on whether verses are present and whether it's a single verse or a range:

```swift
var displayText: String {
    guard let verses else { return "\(book) \(chapter)" }   // "Psalms 23"
    if verses.lowerBound == verses.upperBound {
        return "\(book) \(chapter):\(verses.lowerBound)"     // "John 3:16"
    }
    return "\(book) \(chapter):\(verses.lowerBound)-\(verses.upperBound)" // "John 3:16-18"
}
```

**Parsing — top level.** `parse(_:)` splits the trimmed input on whitespace. It needs at least two tokens (a book and a chapter spec). The **last** token is the chapter/verse part; everything before it is the book name (so "1 Corinthians" survives as two tokens, rejoined):

```swift
let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
guard tokens.count >= 2 else { return nil }

guard let (chapter, verses) = parseChapterVerses(tokens.last!) else { return nil }
let bookInput = tokens.dropLast().joined(separator: " ")
guard let book = BibleBookCatalog.canonical(for: bookInput) else { return nil }
```

Then it sanity-checks the numbers (chapter must be positive, verse lower bound at least 1) and returns the assembled reference. Notice the book name is validated via the catalog — anything it doesn't recognize yields `nil` here.

**Parsing the trailing token.** `parseChapterVerses` handles the three shapes — `13`, `13:4`, `13:4-7`:

```swift
if let colon = token.firstIndex(of: ":") {
    guard let chapter = Int(token[..<colon]) else { return nil }
    let versesPart = token[token.index(after: colon)...]
    if let dash = versesPart.firstIndex(of: "-") {
        guard let start = Int(versesPart[..<dash]),
              let end = Int(versesPart[versesPart.index(after: dash)...]),
              start <= end
        else { return nil }
        return (chapter, start...end)
    }
    guard let single = Int(versesPart) else { return nil }
    return (chapter, single...single)
}
guard let chapter = Int(token) else { return nil }
return (chapter, nil)
```

A single verse is stored as a one-element range (`16...16`). No colon at all means "whole chapter" → `verses == nil`. A reversed range like `7-4` is rejected (`start <= end` fails).

**Worked example: `parse("1cor 13:4-7")`**
1. Split → `["1cor", "13:4-7"]`. Count ≥ 2, good.
2. `parseChapterVerses("13:4-7")`: colon found → chapter `13`; `"4-7"` has a dash → start `4`, end `7`, `4 <= 7` → `(13, 4...7)`.
3. Book input = `"1cor"`; `BibleBookCatalog.canonical(for: "1cor")` → `"1 Corinthians"`.
4. Numbers valid → `BibleReference(book: "1 Corinthians", chapter: 13, verses: 4...7)`.

**Worked example: `parse("Psalm 23")`**
1. Split → `["Psalm", "23"]`.
2. `"23"` has no colon → `(23, nil)` (whole chapter).
3. Catalog: `"Psalm"` → `"Psalms"`.
4. Result: `BibleReference(book: "Psalms", chapter: 23, verses: nil)`.

## How it connects

```
user text ──▶ BibleBookCatalog (book name)
                  ▲
            BibleReferenceParser.parse  ──▶ BibleStore.verses(for:)  ──▶ SlideSplitter  ──▶ ContentRebuilder  ──▶ Slides
```

`ContentRebuilder.rebuildBible` calls `parse` on the operator's typed string. A non-`nil` result is passed to `BibleStore` to fetch verse rows; a `nil` result clears the item's slides (the editor then shows an "unknown reference" state). The rebuilder also writes `reference.displayText` back onto the item, so the field self-corrects ("Psalm 23" → "Psalms 23").

## Gotchas / why it matters

- **`nil` is the contract.** Every failure path — too few tokens, unknown book, non-numeric chapter, reversed verse range — returns `nil`. Callers rely on that single signal to render the "unknown reference" state cleanly instead of crashing or guessing.
- **Whitespace required between book and chapter.** `"John3:16"` won't parse — there must be a space so the split produces ≥ 2 tokens.
- **Whole-chapter is encoded as `verses == nil`**, while a single verse is a degenerate range (`16...16`). Downstream code checks `reference.verses` to decide between a verse-range query and a whole-chapter query.
- **Pure and offline-friendly.** No SwiftData, no UI — just string in, struct (or `nil`) out, making it directly unit-testable.
