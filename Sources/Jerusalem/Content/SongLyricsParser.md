# `SongLyricsParser.swift`

> Parses a free-typed lyrics block (with `[Verse 1]` / `[Chorus]` markers) into ordered `ParsedSongSection` values — and serializes them back.

**Location:** `Sources/Jerusalem/Content/SongLyricsParser.swift`
**Role:** pure parser/namespace (+ the `ParsedSongSection` value type)

## What it does (plain English)

Operators paste hymn lyrics as plain text, using square-bracket markers like `[Verse 1]` and `[Chorus]` to delimit sections. This file converts that text into a structured list of sections (each with a kind, an optional number, and its lyrics), and can convert the list back into the same text format.

It defines `ParsedSongSection` (a SwiftData-free value type so the parser stays pure) and the `SongLyricsParser` namespace with three functions: `parse(_:)` (text → sections), `parseMarker(_:)` (recognizes one `[...]` line), and `format(_:)` (sections → text). Markers are case-insensitive and whitespace-tolerant; any content typed *before* the first marker is treated as an unnumbered Verse, so even a bare lyrics paste produces a usable song.

In the pipeline it's the front of the song flow: `ContentRebuilder.setLyrics` calls `parse`, stores the result as `SongSection` rows, then rebuilds slides; `ContentRebuilder.lyricsText` calls `format` to repopulate the editor.

## Swift you'll meet in this file

| Swift | JS/TS equivalent |
|---|---|
| `struct ParsedSongSection: Equatable, Sendable` | a value record (copied); `Equatable` = `==` works (handy in tests). Model as a TS `interface` |
| `var number: Int?` | `number: number \| null` |
| `enum SongLyricsParser { ... }` | a namespace of static functions |
| `[String: SongSectionKind]` | `Record<string, SongSectionKind>` — alias word → kind |
| `func flush() { ... }` (nested) | a closure/inner function defined inside `parse`, capturing its locals |
| `currentLines.drop(while: { ... })` | `Array.prototype` drop-leading-while — like skipping until a predicate fails |
| `.reversed().drop(while:).reversed()` | trim trailing items by reversing, dropping, reversing back |
| `text.components(separatedBy: .newlines)` | `str.split(/\r?\n/)` |
| `trimmed.hasPrefix("[")` / `.hasSuffix("]")` | `str.startsWith("[")` / `str.endsWith("]")` |
| `trimmed.dropFirst().dropLast()` | slice off first/last char |
| `inner.split(whereSeparator: { $0.isWhitespace })` | `inner.split(/\s+/)` |
| `parts.first.map(String.init)` | optional-map: convert the first part to a String if it exists |
| `Int(parts[1])` | `parseInt` that returns `nil` instead of `NaN` |
| `section.number.map { "[\(...) \($0)]" } ?? "[...]"` | "if number exists build labeled header, else plain" |

## Code walkthrough

**The result type.** Decoupled from SwiftData on purpose:

```swift
struct ParsedSongSection: Equatable, Sendable {
    var kind: SongSectionKind
    var number: Int?
    var lyrics: String
}
```

**TypeScript equivalent**

```ts
type SongSectionKind = "verse" | "chorus" | "bridge" | "tag";

interface ParsedSongSection {
  kind: SongSectionKind;
  number: number | null;
  lyrics: string;
}
```

**Swift syntax:**
- `struct ParsedSongSection: Equatable, Sendable` — value type, copied on assignment. `Equatable` gives a free `==` (so tests can round-trip and assert); `Sendable` = thread-safe to pass. Model as an `interface` in TS.
- `var number: Int?` — optional integer, `number | null`.

**Recognized markers.** A lowercase-word → kind table:

```swift
private static let kindAliases: [String: SongSectionKind] = [
    "verse": .verse, "chorus": .chorus, "bridge": .bridge, "tag": .tag,
]
```

**TypeScript equivalent**

```ts
const kindAliases: Record<string, SongSectionKind> = {
  verse: "verse", chorus: "chorus", bridge: "bridge", tag: "tag",
};
```

**Swift syntax:**
- `[String: SongSectionKind]` — a dictionary literal (`Record<string, ...>`). The values `.verse`, `.chorus` are `enum` cases written in shorthand (type inferred from the dictionary's value type), like the string union members in TS.

**Parsing — the state machine.** `parse` walks the text line by line, accumulating lines into the *current* section. A nested `flush()` closure finalizes the current section whenever a new marker appears (or at the end). It trims leading/trailing blank lines and decides whether to keep the section:

```swift
func flush() {
    let trimmed = currentLines
        .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        .reversed()
        .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        .reversed()
    let lyrics = trimmed.joined(separator: "\n")
    // Only the implicit pre-marker block may be empty — and we skip it.
    if lyrics.isEmpty && !sawMarker { return }
    sections.append(ParsedSongSection(kind: currentKind, number: currentNumber, lyrics: lyrics))
}
```

**TypeScript equivalent**

```ts
// flush() is a nested function closing over currentLines, sawMarker, sections, ...
const flush = () => {
  // drop leading + trailing blank lines (blank == only whitespace)
  let start = 0, end = currentLines.length;
  while (start < end && currentLines[start].trim() === "") start++;
  while (end > start && currentLines[end - 1].trim() === "") end--;
  const lyrics = currentLines.slice(start, end).join("\n");
  // Only the implicit pre-marker block may be empty — and we skip it.
  if (lyrics === "" && !sawMarker) return;
  sections.push({ kind: currentKind, number: currentNumber, lyrics });
};
```

**Swift syntax:**
- `func flush() { ... }` *inside* `parse` — a nested function. It *captures* (closes over) the surrounding mutable locals (`currentLines`, `sawMarker`, `sections`, `currentKind`, `currentNumber`) and can read/mutate them, exactly like a JS inner arrow closing over the outer scope.
- `.drop(while: { ... })` — returns a subsequence with leading elements dropped *while* the predicate holds (stops at the first that fails). To trim the *trailing* blanks too, the code reverses, drops-leading, then reverses back — a common functional trick. `$0` is each line.
- `$0.trimmingCharacters(in: .whitespaces).isEmpty` — "this line is blank (only spaces)."
- `if lyrics.isEmpty && !sawMarker { return }` — `&&` is logical AND, `!` is NOT, just like JS.

The main loop: a marker line triggers `flush()` then resets the "current" state; any other line is appended to the buffer. A final `flush()` closes the last section:

```swift
for rawLine in text.components(separatedBy: .newlines) {
    if let parsed = parseMarker(rawLine) {
        flush()
        currentKind = parsed.kind
        currentNumber = parsed.number
        currentLines = []
        sawMarker = true
    } else {
        currentLines.append(rawLine)
    }
}
flush()
```

**TypeScript equivalent**

```ts
for (const rawLine of text.split(/\r?\n/)) {
  const parsed = parseMarker(rawLine);
  if (parsed != null) {
    flush();
    currentKind = parsed.kind;
    currentNumber = parsed.number;
    currentLines = [];
    sawMarker = true;
  } else {
    currentLines.push(rawLine);
  }
}
flush(); // close the last section
```

**Swift syntax:**
- `if let parsed = parseMarker(rawLine) { ... } else { ... }` — `parseMarker` returns an optional tuple; `if let` unwraps it. Non-nil → it was a marker line; nil → ordinary lyric line.
- `parsed.kind` / `parsed.number` — accessing members of a *labeled tuple* (the return type is `(kind: SongSectionKind, number: Int?)`), so you read fields by name, not position.

Note `currentKind` starts as `.verse` and `sawMarker` as `false`, which is how pre-marker content becomes an unnumbered Verse (but is skipped if it's empty).

**Recognizing a marker.** Must be bracketed; the inner word maps to a known kind, and an optional second token is the number:

```swift
guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
let inner = trimmed.dropFirst().dropLast()
    .trimmingCharacters(in: .whitespaces).lowercased()
...
let parts = inner.split(whereSeparator: { $0.isWhitespace })
guard let head = parts.first.map(String.init),
      let kind = kindAliases[head] else { return nil }
let number: Int? = parts.count >= 2 ? Int(parts[1]) : nil
return (kind, number)
```

**TypeScript equivalent**

```ts
function parseMarker(line: string): { kind: SongSectionKind; number: number | null } | null {
  const trimmed = line.trim();
  if (!trimmed.startsWith("[") || !trimmed.endsWith("]")) return null;
  const inner = trimmed.slice(1, -1).trim().toLowerCase();
  if (inner === "") return null;

  const parts = inner.split(/\s+/);
  const head = parts[0];                       // parts.first.map(String.init)
  const kind = head != null ? kindAliases[head] : undefined;
  if (kind == null) return null;

  const number = parts.length >= 2 ? toInt(parts[1]) : null; // Int(parts[1])
  return { kind, number };
}
```

**Swift syntax:**
- `guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }` — multiple comma-separated conditions in one `guard`; *all* must hold or the `else` runs. Equivalent to `if (!a || !b) return null;`.
- `trimmed.dropFirst().dropLast()` — drop the first and last character (the brackets), yielding a `Substring`; `.lowercased()` then makes a `String`. Like `trimmed.slice(1, -1)`.
- `inner.split(whereSeparator: { $0.isWhitespace })` — split on a character predicate (`(c) => c.isWhitespace`), i.e. `split(/\s+/)`.
- `parts.first.map(String.init)` — `parts.first` is optional (`Substring?`); `.map(String.init)` converts it to `String?` *only if* present (optional-map; `undefined` stays `undefined`). Like `parts[0] != null ? String(parts[0]) : undefined`.
- `parts.count >= 2 ? Int(parts[1]) : nil` — ternary; `Int(parts[1])` is the failable initializer returning `Int?` (nil on non-numeric), modeled as a `toInt` that returns `null`.
- `return (kind, number)` — returns the labeled tuple `(kind:number:)`.

So `[Verse 1]`, `[chorus]`, and `[ Bridge ]` all parse; `[Refrain]` returns `nil` (unknown word) and is treated as a normal lyric line.

**Serializing back.** `format` is the inverse, used to re-pretty-print after a rebuild:

```swift
let header = section.number.map { "[\(section.kind.displayName) \($0)]" }
    ?? "[\(section.kind.displayName)]"
return section.lyrics.isEmpty ? header : "\(header)\n\(section.lyrics)"
```

**TypeScript equivalent**

```ts
const header = section.number != null
  ? `[${section.kind.displayName} ${section.number}]` // labeled
  : `[${section.kind.displayName}]`;                  // plain
return section.lyrics === "" ? header : `${header}\n${section.lyrics}`;
```

**Swift syntax:**
- `section.number.map { "[\(...) \($0)]" } ?? "[\(...)]"` — *optional-map then nil-coalesce*: if `number` is non-nil, run the closure (where `$0` is the unwrapped number) to build the labeled header; otherwise (`??`) fall back to the plain header. Reads as "if number exists, labeled; else plain."
- `section.lyrics.isEmpty ? header : "\(header)\n\(section.lyrics)"` — a ternary choosing header-only vs header-plus-lyrics.

Sections are joined with a blank line between them.

```swift
}.joined(separator: "\n\n")
```

**TypeScript equivalent**

```ts
}).join("\n\n");
```

**Worked example**

Input:
```
[Verse 1]
Amazing grace! How sweet the sound

[Chorus]
My chains are gone
```
→ two `ParsedSongSection`s: `(.verse, 1, "Amazing grace! How sweet the sound")` and `(.chorus, nil, "My chains are gone")`. Feeding those back through `format` reproduces the same block.

## How it connects

```
editor text ──▶ SongLyricsParser.parse ──▶ [ParsedSongSection]
                                                │
                          ContentRebuilder.setLyrics ──▶ SongSection rows (source of truth)
                                                │
                                                ▼
                              SlideSplitter.split(songSections:) ──▶ Slides

SongSection rows ──▶ ContentRebuilder.lyricsText ──▶ SongLyricsParser.format ──▶ editor text
```

It's the upstream-most piece of the *song* pipeline (the Bible flow has its own parser). Downstream, the parsed sections become `SongSection` rows — the authored source of truth — which the splitter and rebuilder turn into slides.

## Gotchas / why it matters

- **Pure and round-trippable.** No SwiftData/UI; `parse` and `format` are near-inverses, so tests can round-trip text → sections → text. `ParsedSongSection` is `Equatable` for easy assertions.
- **Graceful on bare input.** Content before any marker becomes an unnumbered Verse, so pasting raw lyrics with no headers still yields a working song.
- **Empty explicit sections survive; empty implicit ones don't.** `flush()` keeps an empty section only if a marker introduced it (`sawMarker`), so an operator-added blank `[Chorus]` persists while accidental leading blank lines are dropped.
- **Unknown markers fall through as lyrics.** Only the four words in `kindAliases` are recognized; anything else (e.g. `[Refrain]`) is treated as ordinary lyric text, not a section break.
- **Blank-line trimming is per-section.** Leading/trailing blanks inside a section are stripped, but the structure between sections is reconstructed by `format` with a blank-line separator.
