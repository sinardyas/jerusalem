# `SlideSplitter.swift`

> Pure, unit-tested rules that chop authored content — song sections, Bible verses, sermon bodies — into slide-sized `SlideDraft` chunks.

**Location:** `Sources/Jerusalem/Content/SlideSplitter.swift`
**Role:** pure namespace (+ the `SlideDraft` value type)

## What it does (plain English)

A whole verse of a hymn or a long sermon paragraph can't all fit legibly on one projected slide. This file holds the decidable rules for breaking content into reasonable chunks — by line count for lyrics and sermons, one-verse-per-slide for scripture — and labeling those chunks for the operator's grid.

It defines `SlideDraft`, a tiny value type describing one slide-to-be (an optional section label + the text), and `SlideSplitter`, a namespace with three `split(...)` overloads — one each for songs, Bible, and sermon/text. Each returns a flat `[SlideDraft]` array in projection order. The shared workhorse `chunkLines` does the line-budget splitting.

Because it's a caseless `enum` with no SwiftData or UI dependencies, it's directly unit-testable — feed it text, assert on the drafts. `ContentRebuilder` then turns those drafts into real SwiftData rows.

## Swift you'll meet in this file

| Swift | JS/TS equivalent |
|---|---|
| `struct SlideDraft: Equatable, Sendable` | a value record (copied); `Equatable` = `==` works (great for test assertions). Model as a TS `interface` |
| `var sectionLabel: String?` | `sectionLabel: string \| null` |
| `enum SlideSplitter { static func split(...) }` | `export const SlideSplitter = { split() {...} }` |
| three `split(...)` overloads | overloading by argument labels/types — Swift picks the right one |
| `max(1, linesPerSlide)` | `Math.max(1, linesPerSlide)` — guard against 0 |
| `chunks.enumerated().map { index, chunk in ... }` | `chunks.entries()` → `.map((chunk, index) => ...)` |
| `index == 0 ? label : nil` | ternary |
| `.components(separatedBy: "\n\n")` | `str.split("\n\n")` (paragraphs) |
| `.components(separatedBy: .newlines)` | `str.split(/\r?\n/)` |
| `.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))` | trim only spaces/tabs (not newlines) from each line |
| `.filter { !$0.isEmpty }` | `.filter(s => s !== "")` |
| `lines.first?.isEmpty == true` | optional chaining + bool compare: "is the first line present *and* empty?" |
| `current.joined(separator: "\n")` | `arr.join("\n")` |

## Code walkthrough

**The draft.** Only the *first* slide of a section gets a label; continuation slides carry `nil` so the grid doesn't repeat "Verse 1" three times:

```swift
struct SlideDraft: Equatable, Sendable {
    var sectionLabel: String?
    var text: String
}
```

**TypeScript equivalent**

```ts
interface SlideDraft {
  sectionLabel: string | null; // only the first slide of a section is labeled
  text: string;
}
```

**Swift syntax:**
- `struct SlideDraft: Equatable, Sendable` — a *value type* (copied on assignment, never shared). `Equatable` synthesizes `==` so tests can assert exact draft arrays; `Sendable` marks it thread-safe to pass around. In TS it's just an `interface`.
- `var sectionLabel: String?` — optional field; `String | null`.

**Songs.** For each parsed section, build its label, chunk the lyrics, and attach the label to only the first chunk. Empty sections still produce one placeholder slide so the operator can navigate to them:

```swift
let chunks = chunkLines(section.lyrics, perSlide: perSlide)
if chunks.isEmpty {
    drafts.append(SlideDraft(sectionLabel: label, text: ""))
    continue
}
for (index, chunk) in chunks.enumerated() {
    drafts.append(SlideDraft(sectionLabel: index == 0 ? label : nil, text: chunk))
}
```

**TypeScript equivalent**

```ts
const chunks = chunkLines(section.lyrics, perSlide);
if (chunks.length === 0) {
  drafts.push({ sectionLabel: label, text: "" });
  continue;
}
for (const [index, chunk] of chunks.entries()) {
  drafts.push({ sectionLabel: index === 0 ? label : null, text: chunk });
}
```

**Swift syntax:**
- `for (index, chunk) in chunks.enumerated()` — `.enumerated()` yields `(index, element)` tuples (like JS `.entries()`); the `for` loop destructures each into `index` and `chunk`. Note Swift's order is `(index, element)`.
- `index == 0 ? label : nil` — a ternary; `label` is `String?`, so the whole expression is `String?`.
- `continue` — skip to the next loop iteration, same as JS.

**Bible.** One slide per verse — no mid-verse splitting (the renderer auto-fits long verses instead). Each slide gets a footer with the reference + uppercased translation tag:

```swift
return bibleVerses.map { verse in
    let footer = "— \(verse.reference) (\(footerTag))"
    return SlideDraft(sectionLabel: verse.reference,
                      text: "\(verse.text)\n\n\(footer)")
}
```

**TypeScript equivalent**

```ts
return bibleVerses.map((verse) => {
  const footer = `— ${verse.reference} (${footerTag})`;
  return {
    sectionLabel: verse.reference,
    text: `${verse.text}\n\n${footer}`,
  };
});
```

**Swift syntax:**
- `bibleVerses.map { verse in ... }` — trailing-closure `map` with an explicit parameter name `verse` (instead of `$0`), useful when the body is multi-line.
- `"\(verse.text)\n\n\(footer)"` — string interpolation `\(...)` is the template-literal `${...}`.

**Sermon / text.** A title slide first, then one slide per blank-line-separated paragraph, with long paragraphs further chunked by `linesPerSlide`. Each paragraph's first chunk is labeled `"Point N"`:

```swift
let paragraphs = body
    .components(separatedBy: "\n\n")
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }

for (paragraphIndex, paragraph) in paragraphs.enumerated() {
    let chunks = chunkLines(paragraph, perSlide: perSlide)
    for (chunkIndex, chunk) in chunks.enumerated() {
        let label = chunkIndex == 0 ? "Point \(paragraphIndex + 1)" : nil
        drafts.append(SlideDraft(sectionLabel: label, text: chunk))
    }
}
```

**TypeScript equivalent**

```ts
const paragraphs = body
  .split("\n\n")
  .map((p) => p.trim())
  .filter((p) => p.length > 0);

for (const [paragraphIndex, paragraph] of paragraphs.entries()) {
  const chunks = chunkLines(paragraph, perSlide);
  for (const [chunkIndex, chunk] of chunks.entries()) {
    const label = chunkIndex === 0 ? `Point ${paragraphIndex + 1}` : null;
    drafts.push({ sectionLabel: label, text: chunk });
  }
}
```

**Swift syntax:**
- `.components(separatedBy: "\n\n")` — split on a literal substring (paragraph breaks), like `str.split("\n\n")`.
- `.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }` — `$0` is the implicit element; `.whitespacesAndNewlines` is a predefined `CharacterSet`, so this is `.trim()`.

**The line-chunker (shared).** Splits a block into newline-joined groups of at most `perSlide` lines. It trims each line of spaces/tabs (but keeps blank lines *between* content, which matter in hymn layout), and drops leading/trailing blanks:

```swift
var lines = text
    .components(separatedBy: .newlines)
    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) }
while lines.first?.isEmpty == true { lines.removeFirst() }
while lines.last?.isEmpty == true { lines.removeLast() }
guard !lines.isEmpty else { return [] }

var chunks: [String] = []
var current: [String] = []
for line in lines {
    current.append(line)
    if current.count >= perSlide {
        chunks.append(current.joined(separator: "\n"))
        current = []
    }
}
if !current.isEmpty {
    chunks.append(current.joined(separator: "\n"))
}
```

**TypeScript equivalent**

```ts
const lines = text
  .split(/\r?\n/)
  .map((l) => l.replace(/^[ \t]+|[ \t]+$/g, "")); // trim only spaces/tabs
while (lines.length > 0 && lines[0] === "") lines.shift();        // drop leading blanks
while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop(); // drop trailing
if (lines.length === 0) return [];

const chunks: string[] = [];
let current: string[] = [];
for (const line of lines) {
  current.push(line);
  if (current.length >= perSlide) {
    chunks.push(current.join("\n"));
    current = [];
  }
}
if (current.length > 0) {
  chunks.push(current.join("\n"));
}
```

**Swift syntax:**
- `var lines = ...` — `var` makes it mutable (we `removeFirst()`/`removeLast()` later); `let` would be a `const`.
- `.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))` — trims only the characters in the custom set (space, tab) — *not* newlines — so blank lines survive as `""`. The TS analog is a regex that strips leading/trailing spaces and tabs only.
- `while lines.first?.isEmpty == true { ... }` — `lines.first` is `String?` (nil when empty); `?.isEmpty` is `Bool?`; comparing `== true` is true only when the line *exists and* is empty. When `lines` runs out, `first` is nil, `?.isEmpty` is nil, `nil == true` is false → loop stops. This neatly avoids an out-of-bounds check.
- `guard !lines.isEmpty else { return [] }` — early-return an empty array if nothing's left.
- `current.joined(separator: "\n")` — `arr.join("\n")`.

**Labeling.** `displayLabel` shows a section's ordinal for verses always, and for other kinds only when numbered:

```swift
if let number = section.number {
    return "\(section.kind.displayName) \(number)"   // "Verse 2"
}
return section.kind.displayName                      // "Chorus"
```

**TypeScript equivalent**

```ts
if (section.number != null) {
  return `${section.kind.displayName} ${section.number}`; // "Verse 2"
}
return section.kind.displayName;                          // "Chorus"
```

**Swift syntax:**
- `if let number = section.number { ... }` — unwraps the optional `number` into a non-optional `number` for the `if` body; if nil, falls through to the unlabeled `return`. Like `if (section.number != null) { ... }`.

**Worked example: a 4-line verse with `linesPerSlide == 2`**
- `chunkLines` → `["line1\nline2", "line3\nline4"]` (two chunks).
- Song split → two drafts: first `sectionLabel: "Verse 1"`, second `sectionLabel: nil`. The operator's grid shows the header once.

## How it connects

```
SongLyricsParser ──▶ [ParsedSongSection] ─┐
BibleStore       ──▶ [BibleVerse]         ├─▶ SlideSplitter.split(...) ──▶ [SlideDraft] ──▶ ContentRebuilder.materialize ──▶ Slides
item.title/body  ──▶ (String)            ─┘
```

It's the middle stage of the pipeline. Its three callers (all inside `ContentRebuilder`) hand it already-prepared inputs; it hands back `SlideDraft`s, which the rebuilder themes and persists as `Slide`/`SlideElement` rows.

## Gotchas / why it matters

- **Pure and testable by design.** No SwiftData, no UI — `SlideDraft` is `Equatable`, so tests can assert exact draft arrays. This is the unit-tested heart of the authoring pipeline.
- **Label-on-first-chunk-only** is the rule that keeps the slide grid readable; continuation slides intentionally have `nil` labels.
- **One verse never splits across slides.** Scripture relies on the renderer's auto-fit to shrink long verses rather than break a sentence mid-air.
- **Blank-line semantics differ by content.** Sermons split *paragraphs* on `\n\n`; `chunkLines` *preserves* internal blank lines (hymn stanza spacing) while trimming the outer ones.
- **`max(1, linesPerSlide)`** guards against a zero/negative budget that would otherwise never flush a chunk.
- **Empty sections still yield a slide** (songs) so an operator-added empty section remains navigable instead of silently vanishing.
