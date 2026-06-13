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
| `struct BibleReference: Equatable, Sendable` | a value-type record (copied, not shared); `Equatable` = has `==`; `Sendable` = safe to pass across threads. Model as a TS `interface` |
| `var verses: ClosedRange<Int>?` | `verses: {lower:number, upper:number} \| null` — an inclusive range `16...18`, or null = "whole chapter" |
| `var displayText: String { ... }` | a computed getter (like a TS `get displayText()`) |
| `guard let verses else { return ... }` | `if (verses == null) return ...` — an early-exit null check that *unwraps* on success |
| `"\(book) \(chapter)"` | template literal `` `${book} ${chapter}` `` |
| `enum BibleReferenceParser { static func parse(...) }` | `export const BibleReferenceParser = { parse() {...} }` |
| `input.split(whereSeparator: \.isWhitespace)` | `input.split(/\s+/)` — `\.isWhitespace` is a key-path predicate |
| `.map(String.init)` | `.map(x => String(x))` — convert each substring to a real `String` |
| `tokens.last!` | `tokens[tokens.length-1]` with a force-unwrap (crashes if empty — but guarded above) |
| `token.firstIndex(of: ":")` | `str.indexOf(":")`, returning a `String.Index` or `nil` |
| `Int(token[..<colon])` | `parseInt` that returns `null` instead of `NaN` on failure |
| `start...end` | builds the inclusive range value |
| labeled tuple `(Int, ClosedRange<Int>?)` | a fixed-shape pair `[number, Range \| null]`, destructured on return |

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

**TypeScript equivalent**

```ts
interface ClosedRange { lower: number; upper: number; } // inclusive 16..18

interface BibleReference {
  book: string;
  chapter: number;
  verses: ClosedRange | null; // null = whole chapter
}

function displayText(ref: BibleReference): string {
  const { book, chapter, verses } = ref;
  if (verses == null) return `${book} ${chapter}`;          // "Psalms 23"
  if (verses.lower === verses.upper) {
    return `${book} ${chapter}:${verses.lower}`;            // "John 3:16"
  }
  return `${book} ${chapter}:${verses.lower}-${verses.upper}`; // "John 3:16-18"
}
```

**Swift syntax:**
- `struct BibleReference: Equatable, Sendable` — a `struct` is a *value type*: assigning or passing it copies it (no shared mutation), unlike a class/object reference. The `: Equatable, Sendable` are protocol conformances the compiler synthesizes — `Equatable` gives a free `==`, `Sendable` marks it safe to send across threads. In TS just model it as an `interface`.
- `var displayText: String { ... }` — no `=` and no `()`, so this is a *computed property* (a getter that runs each access), like TS `get displayText()`.
- `guard let verses else { return ... }` — `guard let` unwraps the optional `verses` into a non-optional binding *for the rest of the scope*; if it's nil, the `else` must exit. It's an early-return null check that also narrows the type.
- `verses.lowerBound` / `.upperBound` — the inclusive ends of a `ClosedRange`.

**Parsing — top level.** `parse(_:)` splits the trimmed input on whitespace. It needs at least two tokens (a book and a chapter spec). The **last** token is the chapter/verse part; everything before it is the book name (so "1 Corinthians" survives as two tokens, rejoined):

```swift
let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
guard tokens.count >= 2 else { return nil }

guard let (chapter, verses) = parseChapterVerses(tokens.last!) else { return nil }
let bookInput = tokens.dropLast().joined(separator: " ")
guard let book = BibleBookCatalog.canonical(for: bookInput) else { return nil }
```

**TypeScript equivalent**

```ts
const tokens = trimmed.split(/\s+/).map((s) => String(s));
if (tokens.length < 2) return null;

const cv = parseChapterVerses(tokens[tokens.length - 1]); // last token
if (cv == null) return null;
const [chapter, verses] = cv;

const bookInput = tokens.slice(0, -1).join(" ");          // everything before last
const book = BibleBookCatalog.canonical(bookInput);
if (book == null) return null;
```

**Swift syntax:**
- `split(whereSeparator: \.isWhitespace)` — `\.isWhitespace` is a *key-path* used as a predicate: "split wherever a character's `isWhitespace` is true." Think `(c) => c.isWhitespace`.
- `.map(String.init)` — passing an initializer as a function value; `String.init` is `(x) => String(x)`. Needed because `split` yields `Substring`s, not full `String`s.
- `guard let (chapter, verses) = parseChapterVerses(...) else { return nil }` — unwraps the optional tuple *and* destructures it in one move. If `parseChapterVerses` returns nil, bail.
- `tokens.last!` — `.last` is optional (`String?`); the `!` *force-unwraps* it (crashes if nil). Safe here only because the `count >= 2` guard ran first.
- `tokens.dropLast()` — all but the last element, like `tokens.slice(0, -1)`.

Then it sanity-checks the numbers (chapter must be positive, verse lower bound at least 1) and returns the assembled reference. Notice the book name is validated via the catalog — anything it doesn't recognize yields `nil` here.

```swift
guard chapter > 0 else { return nil }
if let verses, verses.lowerBound < 1 { return nil }
return BibleReference(book: book, chapter: chapter, verses: verses)
```

**TypeScript equivalent**

```ts
if (chapter <= 0) return null;
if (verses != null && verses.lower < 1) return null;
return { book, chapter, verses };
```

**Swift syntax:**
- `if let verses, verses.lowerBound < 1` — combines an optional unwrap with a boolean condition: "if `verses` is non-nil *and* its lower bound is < 1". Equivalent to `if (verses != null && verses.lower < 1)`.

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

**TypeScript equivalent**

```ts
function parseChapterVerses(token: string): [number, ClosedRange | null] | null {
  const colon = token.indexOf(":");
  if (colon !== -1) {
    const chapter = toInt(token.slice(0, colon));
    if (chapter == null) return null;
    const versesPart = token.slice(colon + 1);
    const dash = versesPart.indexOf("-");
    if (dash !== -1) {
      const start = toInt(versesPart.slice(0, dash));
      const end = toInt(versesPart.slice(dash + 1));
      if (start == null || end == null || start > end) return null;
      return [chapter, { lower: start, upper: end }];
    }
    const single = toInt(versesPart);
    if (single == null) return null;
    return [chapter, { lower: single, upper: single }];
  }
  const chapter = toInt(token);
  if (chapter == null) return null;
  return [chapter, null]; // whole chapter
}

// Int(...) returns nil on failure rather than NaN — model that explicitly:
function toInt(s: string): number | null {
  if (!/^-?\d+$/.test(s)) return null;
  const n = Number(s);
  return Number.isInteger(n) ? n : null;
}
```

**Swift syntax:**
- `token.firstIndex(of: ":")` returns a `String.Index?` — an opaque cursor into the string (not an `Int`!), or `nil` if absent. `if let colon = ...` unwraps it.
- `token[..<colon]` and `token[token.index(after: colon)...]` are *range subscripts*: `..<colon` is "up to but not including colon" (a one-sided `PartialRangeUpTo`), `index(after: colon)...` is "from just after the colon to the end." These map to `.slice(0, colon)` and `.slice(colon + 1)` — but note JS `.slice` takes integer offsets, while Swift uses `String.Index` because characters can be multi-byte.
- `Int("13")` — Swift's `Int(_:)` failable initializer returns `Int?` (nil on non-numeric), the clean analog of a `parseInt` that rejects `NaN`.
- `start...end` — the *closed range* operator, inclusive on both ends (`4...7` = 4,5,6,7). Compare `0..<n` (half-open, excludes `n`).
- `return (chapter, nil)` — a *tuple* literal; the function's return type `(Int, ClosedRange<Int>?)?` is itself optional (the whole thing can be nil).

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
