# `main.swift`

> A standalone Swift command-line tool that converts one or more OSIS XML Bible exports into the single JSON file (`bible-starter.json`) that the Jerusalem app's `BibleSeeder` reads on first launch.

**Location:** `Tools/build-bible-db/main.swift`
**Role:** Standalone Swift command-line tool (not part of the app target)

## What it does (plain English)

The app ships an offline Bible. Rather than hand-coding thousands of verses, a maintainer downloads real Bible translations in **OSIS XML** (a standard scripture-markup format), and this tool batch-converts them into the compact JSON shape the app expects. So adding the KJV and WEB Bibles becomes one terminal command, not a code change.

You run it like a Node script (`swift Tools/build-bible-db/main.swift ...`). It takes one argument per translation in the form `id:displayName:path`, parses each OSIS file with a streaming XML reader, maps OSIS book codes (`Gen`, `1Cor`, …) to the app's canonical names (`Genesis`, `1 Corinthians`, …), collects every verse, and prints one big JSON document to **stdout**. You redirect that into `Sources/Jerusalem/Resources/bible-starter.json`, rebuild the app, and the new corpus is bundled.

It's a *maintainer* tool — run occasionally when the Bible data changes, never at app launch. It deliberately handles only the 66-book Protestant canon, drops footnotes/cross-references, and uses Foundation only (no package manifest, no dependencies).

## Swift you'll meet in this file

| Swift idiom | Node equivalent |
| --- | --- |
| `#!/usr/bin/env swift` + top-level statements | a script with a shebang; top-level code is the entry point (like a bare `.js` file) |
| `CommandLine.arguments` | `process.argv` |
| `Array(CommandLine.arguments.dropFirst())` | `process.argv.slice(1)` — drop the program name |
| `FileManager.default` | the `fs` module |
| `FileHandle.standardError.write(Data(...))` | `process.stderr.write(...)` |
| `FileHandle.standardOutput.write(data)` | `process.stdout.write(...)` |
| `exit(64)` / `exit(70)` | `process.exit(64)` (sysexits-style codes: 64 = usage error, 70 = internal/parse error) |
| `struct Job { let ... }` | a plain immutable record/object |
| `String?` (optional) | `string | null`; `??` is `||`/nullish, `?.` is optional chaining |
| `XMLParser` + `XMLParserDelegate` | a SAX-style streaming XML parser (callbacks per tag), like `sax`/`expat` in Node |
| `struct ...: Encodable` + `JSONEncoder` | a type that `JSON.stringify` knows how to serialize |
| `try` / `throws` / `catch` | exceptions |
| `enum`-free `switch element { case "verse": }` | `switch` on a string |

## Code walkthrough

### 1. Parse the CLI arguments
`parseArgs` splits each argument on `:` into exactly three parts (`maxSplits: 2` so a colon inside the display name is fine), lowercases the id, and verifies the file exists. Bad arguments accumulate into an `errors` array rather than crashing.

```swift
let parts = arg.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
guard parts.count == 3 else {
    errors.append("Expected `id:displayName:path` — got `\(arg)`")
    continue
}
```

Top-level code then reads `CommandLine.arguments`, prints a usage message to stderr and `exit(64)` if no args were given, and `exit(64)` if any argument was malformed or pointed at a missing file.

### 2. The OSIS book map
A `[String: String]` dictionary maps the canonical SBL three-letter OSIS book codes to the app's display names — `"Gen": "Genesis"`, `"1Cor": "1 Corinthians"`, `"Rev": "Revelation"`, etc. Only these 66 books are recognized; anything else is treated as out-of-canon and skipped.

### 3. The streaming OSIS reader
`OSISReader` is an `XMLParserDelegate` (a SAX handler) that walks the XML once and collects `Verse` values. It copes with **both** OSIS verse encodings:

- **Wrapped:** `<verse osisID="John.3.16">text</verse>` — the close tag is the flush point.
- **Milestone:** `<verse sID="John.3.16"/> text <verse eID="John.3.16"/>` — start and end are separate self-closing tags.

On a `<verse>` start with an `osisID`/`sID`, it flushes any open verse and opens a new one; on an `eID` (or a `</verse>`), it flushes. A `suppressDepth` counter ignores text inside `<note>`, `<reference>`, and `<rdg>` (variant readings) so footnotes don't leak into verse text.

```swift
func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard openVerse != nil, suppressDepth == 0 else { return }
    openText.append(string)
}
```

`flushOpenVerse` collapses runs of whitespace/newlines to single spaces and appends the verse if non-empty. `decodeOSISID` splits an id like `1Cor.13.4` into `(book, chapter, number)`, taking the first reference if a span is given, and returns `nil` (recording the unknown code in `skipped`) for non-canon books.

### 4. Encode and emit JSON
Three `Encodable` structs define the output shape: `OutputRoot { version, note, translations }`, each `OutputTranslation { id, displayName, verses }`, each `OutputVerse { book, chapter, number, text }`. The run loop parses every job, logs verse counts and any skipped books to stderr, builds the root, and prints pretty-printed, sorted-key JSON to stdout.

```swift
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(root)
FileHandle.standardOutput.write(data)
```

`sortedKeys` keeps the output diff-stable across runs; the `note` field embeds an ISO-8601 timestamp recording when it was built.

## How to run it

This is a maintainer command, run from the repo root, occasionally — not part of the build and never at app launch.

```sh
swift Tools/build-bible-db/main.swift \
    kjv:"King James Version":/path/to/kjv.osis.xml \
    web:"World English Bible":/path/to/web.osis.xml \
    > Sources/Jerusalem/Resources/bible-starter.json
```

- Each argument is `id:displayName:path`. The `id` is lowercased; the `displayName` may contain spaces.
- **stdout** is the JSON corpus — redirect it into `bible-starter.json`.
- **stderr** carries progress (`kjv: 31102 verses`), a note about any skipped non-canon books, and any errors.
- Exit codes: `64` for a usage/argument error (no args, malformed `id:displayName:path`, missing file), `70` for a parse error inside an OSIS file. After regenerating the JSON, rebuild the app so the new corpus is bundled.

## How it connects

The tool's only output is `bible-starter.json`. The app's `BibleSeeder` reads that bundled resource on an empty store and populates the offline `BibleVerse` rows — the data behind the reference parser, the verse store, and the verse splitter (see the Phase 7 Bible pipeline). Change the source OSIS files, re-run this tool, rebuild — and the app ships the new Bibles.
