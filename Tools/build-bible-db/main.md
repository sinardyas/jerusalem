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

**TypeScript equivalent (Node.js)**

```ts
// split on ":" into at most 3 parts (a colon inside displayName is fine).
const [idPart, namePart, ...rest] = arg.split(":");
const parts = rest.length ? [idPart, namePart, rest.join(":")] : [idPart, namePart];
if (parts.length !== 3) {
  errors.push(`Expected \`id:displayName:path\` — got \`${arg}\``);
  continue;
}
```

**Swift syntax:**
- `arg.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)` — split into at most `2 + 1 = 3` pieces (so a `:` in the display name survives), keeping empties. JS `String.split` has no `maxSplits`, so we rejoin the tail manually.
- `guard parts.count == 3 else { … }` — a *guard*: assert a condition and bail (here `continue`) in the `else` if it fails. The happy path keeps flowing un-nested below. Like an early-return `if (!ok) { continue; }`.
- `errors.append(…)` — array push (`.push`).
- `"… `\(arg)` …"` — string interpolation; `\(arg)` is `${arg}`. The backticks are literal text here, not Swift syntax.

Top-level code then reads `CommandLine.arguments`, prints a usage message to stderr and `exit(64)` if no args were given, and `exit(64)` if any argument was malformed or pointed at a missing file.

```swift
let argv = Array(CommandLine.arguments.dropFirst())
guard !argv.isEmpty else {
    FileHandle.standardError.write(Data("usage: …\n".utf8))
    exit(64)
}
let (jobs, argErrors) = parseArgs(argv)
if !argErrors.isEmpty {
    for error in argErrors { FileHandle.standardError.write(Data("error: \(error)\n".utf8)) }
    exit(64)
}
```

**TypeScript equivalent (Node.js)**

```ts
const argv = process.argv.slice(2);   // drop `node` and the script path
if (argv.length === 0) {
  process.stderr.write("usage: …\n");
  process.exit(64);
}
const { jobs, errors: argErrors } = parseArgs(argv);
if (argErrors.length > 0) {
  for (const error of argErrors) process.stderr.write(`error: ${error}\n`);
  process.exit(64);
}
```

**Swift syntax:**
- `CommandLine.arguments` — the process args array; element `[0]` is the program path. `.dropFirst()` drops it (≈ `process.argv.slice(1)`; in Node `argv[0]` is `node` and `[1]` the script, hence `.slice(2)` there).
- `let (jobs, argErrors) = parseArgs(argv)` — *tuple destructuring*: the function returns a labeled tuple `(jobs:, errors:)` and we bind both at once. Like `const { jobs, errors } = …`.
- `FileHandle.standardError.write(Data("…".utf8))` — writes raw bytes to stderr. `"…".utf8` is the string's UTF-8 view; `Data(...)` wraps it as bytes. Node's `process.stderr.write` takes the string directly.
- `exit(64)` — terminate with a status code. `64` follows BSD `sysexits.h` (`EX_USAGE`). Node: `process.exit(64)`.

### 2. The OSIS book map
A `[String: String]` dictionary maps the canonical SBL three-letter OSIS book codes to the app's display names — `"Gen": "Genesis"`, `"1Cor": "1 Corinthians"`, `"Rev": "Revelation"`, etc. Only these 66 books are recognized; anything else is treated as out-of-canon and skipped.

```swift
let osisBookMap: [String: String] = [
    "Gen": "Genesis", "Exod": "Exodus", /* … */ "Rev": "Revelation",
]
```

**TypeScript equivalent (Node.js)**

```ts
const osisBookMap: Record<string, string> = {
  Gen: "Genesis", Exod: "Exodus", /* … */ Rev: "Revelation",
};
```

**Swift syntax:**
- `[String: String]` — a dictionary type, key→value. `Record<string, string>` (or a plain `{}`) in TS. The literal uses `:` between key and value, just like a JS object.

### 3. The streaming OSIS reader
`OSISReader` is an `XMLParserDelegate` (a SAX handler) that walks the XML once and collects `Verse` values. It copes with **both** OSIS verse encodings:

- **Wrapped:** `<verse osisID="John.3.16">text</verse>` — the close tag is the flush point.
- **Milestone:** `<verse sID="John.3.16"/> text <verse eID="John.3.16"/>` — start and end are separate self-closing tags.

On a `<verse>` start with an `osisID`/`sID`, it flushes any open verse and opens a new one; on an `eID` (or a `</verse>`), it flushes. A `suppressDepth` counter ignores text inside `<note>`, `<reference>`, and `<rdg>` (variant readings) so footnotes don't leak into verse text.

```swift
final class OSISReader: NSObject, XMLParserDelegate {
    var verses: [Verse] = []
    private var openVerse: (book: String, chapter: Int, number: Int)?
    private var suppressDepth = 0

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch element {
        case "verse":
            if let osisID = attributes["osisID"] ?? attributes["sID"] {
                flushOpenVerse()
                openVerse = decodeOSISID(osisID)
                openText = ""
            } else if attributes["eID"] != nil {
                flushOpenVerse()
            }
        case "note", "reference", "rdg":
            suppressDepth += 1
        default:
            break
        }
    }
}
```

**TypeScript equivalent (Node.js)**

```ts
// analogy: XMLParser + XMLParserDelegate ≈ a SAX parser (e.g. `sax`/`saxes`)
//          whose callbacks fire per opening/closing tag and text chunk.
import { SaxesParser } from "saxes";

class OSISReader {
  verses: Verse[] = [];
  private openVerse: { book: string; chapter: number; number: number } | null = null;
  private suppressDepth = 0;

  onOpenTag(element: string, attributes: Record<string, string>) {
    switch (element) {
      case "verse": {
        const osisID = attributes["osisID"] ?? attributes["sID"];
        if (osisID != null) {
          this.flushOpenVerse();
          this.openVerse = this.decodeOSISID(osisID);
          this.openText = "";
        } else if (attributes["eID"] != null) {
          this.flushOpenVerse();
        }
        break;
      }
      case "note":
      case "reference":
      case "rdg":
        this.suppressDepth += 1;
        break;
      default:
        break;
    }
  }
}
```

**Swift syntax:**
- `final class OSISReader: NSObject, XMLParserDelegate` — a class that subclasses `NSObject` and *conforms to* the `XMLParserDelegate` protocol (an interface of optional callback methods). The parser calls these `func parser(_:didStart…)` methods as it streams — exactly a SAX handler. (Conforming = `implements` in TS.)
- `var verses: [Verse] = []` vs `private var …` — `var` = mutable property; `private` hides it outside the class. (`let` would be a constant.)
- `(book: String, chapter: Int, number: Int)?` — an *optional labeled tuple*: either a 3-field group or `nil`. TS: `{ book; chapter; number } | null`.
- `switch element { case "verse": … default: break }` — Swift `switch` is exhaustive and does **not** fall through, so each `case` ends implicitly; `default: break` is the catch-all no-op. `case "note", "reference", "rdg":` matches any of three strings. In TS you stack `case` labels and add explicit `break`s.
- `if let osisID = attributes["osisID"] ?? attributes["sID"]` — *optional binding*: try `osisID`, else `sID` (`??` is the nil-coalescing/`??` operator); if the result is non-`nil`, bind it to `osisID` and run the block. Dictionary subscripting returns an optional (the key may be missing).
- `attributes["eID"] != nil` — checks the key exists; `!= null` in TS.

```swift
func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard openVerse != nil, suppressDepth == 0 else { return }
    openText.append(string)
}
```

**TypeScript equivalent (Node.js)**

```ts
onText(text: string) {
  if (this.openVerse == null || this.suppressDepth !== 0) return;   // guard
  this.openText += text;
}
```

**Swift syntax:**
- `guard openVerse != nil, suppressDepth == 0 else { return }` — guard with two comma-separated conditions (both must hold, like `&&`); if either fails, `return` early. So characters are only collected while a verse is open and we're not inside a suppressed note.

`flushOpenVerse` collapses runs of whitespace/newlines to single spaces and appends the verse if non-empty. `decodeOSISID` splits an id like `1Cor.13.4` into `(book, chapter, number)`, taking the first reference if a span is given, and returns `nil` (recording the unknown code in `skipped`) for non-canon books.

```swift
private func decodeOSISID(_ raw: String) -> (book: String, chapter: Int, number: Int)? {
    let first = raw.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? raw
    let parts = first.split(separator: ".").map(String.init)
    guard parts.count >= 3,
          let chapter = Int(parts[1]),
          let number = Int(parts[2])
    else { return nil }
    guard let book = osisBookMap[parts[0]] else {
        if !skipped.contains(parts[0]) { skipped.append(parts[0]) }
        return nil
    }
    return (book, chapter, number)
}
```

**TypeScript equivalent (Node.js)**

```ts
private decodeOSISID(raw: string): { book: string; chapter: number; number: number } | null {
  const first = raw.split(/\s+/).filter(Boolean)[0] ?? raw;   // take first reference of a span
  const parts = first.split(".");
  const chapter = Number.parseInt(parts[1], 10);
  const number = Number.parseInt(parts[2], 10);
  if (parts.length < 3 || Number.isNaN(chapter) || Number.isNaN(number)) return null;
  const book = osisBookMap[parts[0]];
  if (book == null) {
    if (!this.skipped.includes(parts[0])) this.skipped.push(parts[0]);
    return null;
  }
  return { book, chapter, number };
}
```

**Swift syntax:**
- `raw.split(whereSeparator: { $0.isWhitespace })` — split using a *predicate closure*: `{ $0.isWhitespace }` returns true at each whitespace char (`$0` is the current character). Like `.split(/\s+/)`.
- `.first.map(String.init) ?? raw` — `first` is optional; `.map(String.init)` converts the substring to a `String` *only if* it exists (Optional's `map`), then `?? raw` supplies a fallback. In TS, `[0] ?? raw`.
- `Int(parts[1])` — a *failable* string→int conversion: returns `Int?`, `nil` if the string isn't numeric (≈ `parseInt` + `Number.isNaN` check). Bound with `let chapter = Int(parts[1])` inside the `guard`, so all three conditions must pass or we `return nil`.
- `.map(String.init)` — passes the `String.init` initializer as the transform function (point-free), like `.map(String)`.
- `if !skipped.contains(parts[0]) { skipped.append(parts[0]) }` — dedupe-then-push; `.contains` ≈ `.includes`, `.append` ≈ `.push`.

### 4. Encode and emit JSON
Three `Encodable` structs define the output shape: `OutputRoot { version, note, translations }`, each `OutputTranslation { id, displayName, verses }`, each `OutputVerse { book, chapter, number, text }`. The run loop parses every job, logs verse counts and any skipped books to stderr, builds the root, and prints pretty-printed, sorted-key JSON to stdout.

```swift
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(root)
FileHandle.standardOutput.write(data)
```

**TypeScript equivalent (Node.js)**

```ts
// .sortedKeys → sort object keys so the output diff is stable across runs.
const sortKeys = (_k: string, v: unknown) =>
  v && typeof v === "object" && !Array.isArray(v)
    ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => a.localeCompare(b)))
    : v;
const json = JSON.stringify(root, sortKeys, 2);   // 2 = .prettyPrinted
process.stdout.write(json);
```

**Swift syntax:**
- `struct OutputRoot: Encodable` — a value type conforming to `Encodable`; the compiler synthesizes the serialization, so `JSONEncoder` can turn it into JSON with zero boilerplate (the field names become JSON keys). The analogue is "any plain object `JSON.stringify` accepts."
- `JSONEncoder()` / `encoder.outputFormatting = [.prettyPrinted, .sortedKeys]` — configure the encoder: `.prettyPrinted` indents, `.sortedKeys` orders keys for diff-stable output. The `[…]` is an *option set* (a set of flags), passed together. `JSON.stringify(obj, replacer, 2)` is the rough Node match.
- `try encoder.encode(root)` — `encode` can throw (e.g. a non-encodable value); `try` propagates it. Returns `Data` (bytes).
- `FileHandle.standardOutput.write(data)` — writes the bytes to stdout (`process.stdout.write`).

`sortedKeys` keeps the output diff-stable across runs; the `note` field embeds an ISO-8601 timestamp recording when it was built.

```swift
let root = OutputRoot(
    version: 1,
    note: "Built by Tools/build-bible-db from OSIS XML on \(ISO8601DateFormatter().string(from: .now)).",
    translations: translations)
```

**TypeScript equivalent (Node.js)**

```ts
const root: OutputRoot = {
  version: 1,
  note: `Built by Tools/build-bible-db from OSIS XML on ${new Date().toISOString()}.`,
  translations,
};
```

**Swift syntax:**
- `ISO8601DateFormatter().string(from: .now)` — formats the current instant as an ISO-8601 string; `.now` is shorthand for `Date.now`. Node: `new Date().toISOString()`.
- `\(…)` — string interpolation again (`${…}`).

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

## Glossary (Swift → Node.js/TS)

- **`#!/usr/bin/env swift` + top-level code** → a shebang script whose bare statements are the entry point (a plain `.js`/`.ts` run directly).
- **`CommandLine.arguments` / `.dropFirst()`** → `process.argv` / `.slice(1)` (Node: `.slice(2)` to skip `node` + script).
- **`FileManager.default` / `URL(fileURLWithPath:)`** → the `fs` module / a file path.
- **`FileHandle.standardOutput/standardError.write(Data("…".utf8))`** → `process.stdout/stderr.write("…")`.
- **`exit(64)` / `exit(70)`** → `process.exit(64/70)` (sysexits: 64 = usage, 70 = internal/parse).
- **`guard <cond> else { return }`** → early-return guard (`if (!cond) return;`); supports comma-separated conditions (`&&`) and optional binding.
- **Optionals (`T?`, `if let`, `??`, `?.`, `.map`)** → `T | null`; optional binding; `??`; optional chaining; map-if-present.
- **`Int("5")` (failable init)** → `parseInt` + `Number.isNaN` check.
- **`switch s { case "a", "b": … default: break }`** → `switch` with no fall-through; stacked `case`s; `default`.
- **`struct X { let … }`** → a plain immutable record/object.
- **`[String: String]`** → `Record<string, string>` / `{}`.
- **`[T]` / `.append` / `.contains` / `.split` / `.joined`** → `T[]` / `.push` / `.includes` / `.split` / `.join`.
- **Closures / trailing closure / `$0`** → arrow functions; `{ … }` as last arg; `$0` is the first implicit parameter.
- **Tuple `(book:, chapter:, number:)` + destructuring `let (a, b) = …`** → `{ book, chapter, number }` + `const { a, b } = …`.
- **`XMLParser` + `XMLParserDelegate`** → a SAX parser with per-tag callbacks (`// analogy:` `sax`/`saxes`).
- **`Encodable` + `JSONEncoder` (`.prettyPrinted`, `.sortedKeys`)** → `JSON.stringify(obj, replacer, 2)` with a key-sorting replacer.
- **`try` / `throws` / `catch`** → exceptions / `try`/`catch`.
- **String interpolation `\(x)`** → `${x}`.
- **`ISO8601DateFormatter().string(from: .now)`** → `new Date().toISOString()`.
