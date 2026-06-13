# `SongContentTests.swift`

> The Phase 6 gate: a lyrics/sermon text block with `[Verse 1]` / `[Chorus]` markers parses into sections, splits into well-labeled slides, rebuilds through the same path the in-app editor uses, and runs end-to-end as a live program through `LiveState`.

**Location:** `Tests/JerusalemTests/SongContentTests.swift`
**Role:** XCTest unit tests

## What it does (plain English)

This is the content-authoring pipeline test. A user types raw lyrics with section markers; the app must turn that into slides. The pipeline has four stages, and this file walks each:

1. **Parser** — `SongLyricsParser.parse` splits a text block on `[Verse 1]` / `[Chorus]` markers into `ParsedSongSection` values (kind, optional number, lyrics body).
2. **Splitter** — `SlideSplitter.split` chops each section into slide-sized chunks honoring `linesPerSlide`, labeling only the *first* slide of a section. It also handles sermons (a "Title" slide then "Point N" slides).
3. **Rebuilder** — `ContentRebuilder` materializes those drafts into real `Slide` rows on an `Item`, keeping the authored `SongSection` rows as the source of truth so re-splitting never loses the original text.
4. **Live program** — `LiveState.programSlides(for:)` snapshots an item into an immutable program, then `arm` / `next` drive it slide by slide, exactly like the operator's keyboard.

Because every stage is pure logic or SwiftData, the whole pipeline is testable headlessly — no window, no video.

## XCTest you'll meet in this file

| XCTest API | Jest equivalent |
| --- | --- |
| `func testFoo()` / `func testFoo() throws` | `it('foo', ...)` |
| `XCTAssertEqual(a, b)` | `expect(a).toEqual(b)` |
| `XCTAssertEqual(arr.map(\.kind), [...])` | `expect(arr.map(x => x.kind)).toEqual([...])` (`\.kind` is a key-path shorthand) |
| `XCTAssertNil(x)` / `XCTAssertNotNil` | `expect(x).toBeNull()` / not |
| `try XCTUnwrap(optional)` | assert-non-null-and-return |
| `@MainActor` | runs on the main thread (SwiftData + `LiveState`) |
| in-memory SwiftData (`isStoredInMemoryOnly: true`) | a throwaway per-test database |

## The tests, one by one

### `testParsesNumberedAndUnnumberedMarkers`
`[Verse 1]` → a verse section with `number == 1`; `[Chorus]` → a chorus with `number == nil`. The body text is captured per section. Catches the parser losing the section number or merging sections.

```swift
let lyrics = """
[Verse 1]
line one
line two
[Chorus]
my chains are gone
"""
let sections = SongLyricsParser.parse(lyrics)
XCTAssertEqual(sections.count, 2)
XCTAssertEqual(sections[0].number, 1)
XCTAssertNil(sections[1].number)
```

**TypeScript equivalent (Jest)**

```ts
const lyrics = `[Verse 1]
line one
line two
[Chorus]
my chains are gone`;
const sections = SongLyricsParser.parse(lyrics);
expect(sections.length).toEqual(2);
expect(sections[0].number).toEqual(1);
expect(sections[1].number).toBeNull();
```

**Swift syntax:**
- `"""…"""` — a *multi-line string literal* (triple-quoted), like a JS template literal (backticks). Leading indentation is stripped relative to the closing `"""`.
- `sections.count` — arrays expose `.count`, not `.length`.
- `sections[0].number` — `number` is an optional `Int?`; `XCTAssertNil` checks it's `nil` (`null`).

### `testMarkersAreCaseInsensitive`
`[VERSE 2]` and `[ chorus ]` (note the spaces and caps) still parse to `.verse` / `.chorus`. Catches a too-strict marker regex.

```swift
let sections = SongLyricsParser.parse("[VERSE 2]\nfoo\n[ chorus ]\nbar")
XCTAssertEqual(sections.map(\.kind), [.verse, .chorus])
```

**TypeScript equivalent (Jest)**

```ts
const sections = SongLyricsParser.parse("[VERSE 2]\nfoo\n[ chorus ]\nbar");
expect(sections.map(s => s.kind)).toEqual([SectionKind.verse, SectionKind.chorus]);
```

**Swift syntax:**
- `sections.map(\.kind)` — `\.kind` is a *key-path* (a first-class reference to the `kind` property) used as the map transform. Equivalent to `s => s.kind`.
- `[.verse, .chorus]` — an array literal of enum-case shorthands; the element type is inferred, so `.verse` means `SectionKind.verse`.

### `testBareLyricsBecomeASingleVerse`
Lyrics with *no* markers become one unnumbered `.verse`. Catches an empty result when the user doesn't use markers.

### `testUnknownBracketLineIsNotAMarker`
`[Refrain]` isn't in the MVP marker vocabulary, so it must **not** split a section — it's kept as literal content. Catches an unknown bracket silently eating a line or starting a phantom section.

```swift
XCTAssertEqual(sections.count, 1)
XCTAssertTrue(sections[0].lyrics.contains("[Refrain]"))
```

**TypeScript equivalent (Jest)**

```ts
expect(sections.length).toEqual(1);
expect(sections[0].lyrics.includes("[Refrain]")).toBe(true);
```

**Swift syntax:**
- `lyrics.contains("[Refrain]")` — substring containment on a `String`; like JS `.includes(...)`.

### `testFormatRoundTripsBackThroughParser`
`SongLyricsParser.format(sections)` produces text that parses back to the *same* sections. Proves parse/format are inverses (so the editor can round-trip the authored text). Catches formatting that drifts from the parser's grammar.

```swift
let original = SongLyricsParser.parse("[Verse 1]\na\nb\n\n[Chorus]\nc")
let formatted = SongLyricsParser.format(original)
XCTAssertEqual(SongLyricsParser.parse(formatted), original)
```

**TypeScript equivalent (Jest)**

```ts
const original = SongLyricsParser.parse("[Verse 1]\na\nb\n\n[Chorus]\nc");
const formatted = SongLyricsParser.format(original);
expect(SongLyricsParser.parse(formatted)).toEqual(original);
```

**Swift syntax:**
- `XCTAssertEqual(parsed, original)` — comparing two arrays of `ParsedSongSection`. This works because `ParsedSongSection` is `Equatable` (a `struct` of equatable fields gets `==` synthesized for free), so the compare is deep/structural — like Jest's `toEqual`.

### `testSplitterHonorsLinesPerSlide`
Five lines at `linesPerSlide: 2` → three slide drafts: `["l1\nl2", "l3\nl4", "l5"]`. Catches the wrong chunking or a dropped trailing line.

```swift
let section = ParsedSongSection(kind: .verse, number: 1, lyrics: "l1\nl2\nl3\nl4\nl5")
let drafts = SlideSplitter.split(songSections: [section], linesPerSlide: 2)
XCTAssertEqual(drafts.count, 3)
XCTAssertEqual(drafts[0].text, "l1\nl2")
```

**TypeScript equivalent (Jest)**

```ts
const section = new ParsedSongSection({ kind: SectionKind.verse, number: 1, lyrics: "l1\nl2\nl3\nl4\nl5" });
const drafts = SlideSplitter.split({ songSections: [section], linesPerSlide: 2 });
expect(drafts.length).toEqual(3);
expect(drafts[0].text).toEqual("l1\nl2");
```

**Swift syntax:**
- `split(songSections:linesPerSlide:)` — both arguments are labeled; TS models this as an options object.

### `testOnlyFirstSlideOfSectionGetsTheLabel`
Only the first draft of a section carries `sectionLabel == "Verse 1"`; subsequent drafts have `nil`. This keeps "Verse 1" from repeating on every continuation slide.

### `testSermonSplitProducesTitleAndPointSlides`
A sermon split yields a `"Title"` slide (the sermon title) followed by `"Point 1"`, `"Point 2"`, `"Point 3"` from blank-line-separated paragraphs. Catches sermon structure being mislabeled.

```swift
XCTAssertEqual(drafts.first?.sectionLabel, "Title")
XCTAssertEqual(drafts.dropFirst().map(\.sectionLabel), ["Point 1", "Point 2", "Point 3"])
```

**TypeScript equivalent (Jest)**

```ts
expect(drafts[0]?.sectionLabel).toEqual("Title");
expect(drafts.slice(1).map(d => d.sectionLabel)).toEqual(["Point 1", "Point 2", "Point 3"]);
```

**Swift syntax:**
- `drafts.first?.sectionLabel` — `first` returns an optional (array might be empty); `?.` reads `.sectionLabel` only if non-`nil`. Like `drafts[0]?.sectionLabel`.
- `drafts.dropFirst()` — returns the array without its first element (non-mutating), like `drafts.slice(1)`.

### `testEditingLyricsRebuildsSlidesAndDrivesLiveProgram` `@MainActor throws`
The actual gate. It sets full "Amazing Grace" lyrics on a song (two verse lines + a chorus), expects exactly 3 slides with labels `["Verse 1", nil, "Chorus"]` and the correct first-slide text. Then it builds a `LiveState`, arms the program via `LiveState.programSlides(for: song)`, and presses `next()` three times, asserting `liveSlideID` lands on slides 0, 1, 2 in turn — a full keyboard run-through.

```swift
let container = try ModelContainer(
    for: Persistence.schema,
    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
let context = ModelContext(container)
// ...
live.arm(program)
live.next()                              // first press starts at slide 0
XCTAssertEqual(live.liveSlideID, program[0].id)
```

**TypeScript equivalent (Jest)**

```ts
// analogy: in-memory ModelContainer ≈ a throwaway SQLite/Prisma DB per-test.
const container = await openInMemoryDb(Persistence.schema);
const context = container.newContext();
// ...
live.arm(program);
live.next();                              // first press starts at slide 0
expect(live.liveSlideID).toEqual(program[0].id);
```

**Swift syntax:**
- `@MainActor` — pins the test to the main thread (SwiftData + `LiveState` are main-actor); no JS analogue.
- `ModelConfiguration(isStoredInMemoryOnly: true)` — a SwiftData store that lives only in RAM and is discarded at test end — the standard "throwaway test DB."
- `program[0].id` — `program` is a value-type array; `.id` is the snapshot's stable identifier the live navigator tracks.

### `testChangingLinesPerSlideRebuildsWithoutLosingLyrics` `@MainActor throws`
Four lines at `linesPerSlide: 4` → 1 slide; change to `2` and rebuild → 2 slides. Crucially, the original lyrics still live in `orderedSongSections.first?.lyrics` unchanged. This is the payoff of keeping `SongSection` rows as the source of truth — re-splitting is non-destructive.

```swift
song.linesPerSlide = 2
ContentRebuilder.rebuild(song)
XCTAssertEqual(song.orderedSlides.count, 2)
XCTAssertEqual(song.orderedSongSections.first?.lyrics, "a\nb\nc\nd")
```

**TypeScript equivalent (Jest)**

```ts
song.linesPerSlide = 2;
ContentRebuilder.rebuild(song);
expect(song.orderedSlides.length).toEqual(2);
expect(song.orderedSongSections[0]?.lyrics).toEqual("a\nb\nc\nd");
```

### `testSermonRebuildProducesTitleThenPoints` `@MainActor throws`
`ContentRebuilder.setBody` on a `.text` item produces slides labeled `["Title", "Point 1", "Point 2", "Point 3"]`, with the title slide carrying the item title text. The rebuilder equivalent of the splitter sermon test.

### `testRebuiltSlideUsesItemTheme` `@MainActor throws`
A rebuilt slide inherits its item's `Theme` — background `#112233`, font `Helvetica` at `64`, text color `#ABCDEF` — confirming the theme is applied during materialization, not hard-coded.

```swift
let slide = try XCTUnwrap(song.orderedSlides.first)
XCTAssertEqual(slide.backgroundColorHex, "#112233")
let element = try XCTUnwrap(slide.orderedElements.first)
XCTAssertEqual(element.fontName, "Helvetica")
```

**TypeScript equivalent (Jest)**

```ts
const slide = song.orderedSlides[0];
expect(slide).not.toBeNull();             // XCTUnwrap(orderedSlides.first)
expect(slide!.backgroundColorHex).toEqual("#112233");
const element = slide!.orderedElements[0];
expect(element).not.toBeNull();
expect(element!.fontName).toEqual("Helvetica");
```

**Swift syntax:**
- `try XCTUnwrap(song.orderedSlides.first)` — `first` is optional; `XCTUnwrap` fails the test if the array is empty, otherwise hands back the unwrapped `Slide`. Lets the next lines use `slide` non-optionally.

## How it connects

Exercises `SongLyricsParser` (parse/format), `ParsedSongSection`, `SlideSplitter` (`split(songSections:...)` and `split(sermonTitle:body:...)`), `ContentRebuilder` (`setLyrics`, `setBody`, `rebuild`), the SwiftData models `Item` / `Slide` / `SlideElement` / `SongSection` / `Theme`, and `LiveState` (`programSlides`, `arm`, `next`, `liveSlideID`).

## What it does NOT cover

Every assertion is pure logic, SwiftData, or `LiveState` — no AppKit window, no AVFoundation. The actual on-screen appearance of the slides and the operator's live experience are verified by running the app.

## Glossary (Swift → TS/Jest/Node)

- **`final class FooTests: XCTestCase`** → `describe("Foo", ...)`.
- **`func testX()` / `throws`** → `it("x", ...)`; `throws` means a thrown error fails the test.
- **`@MainActor`** → run on the main thread (SwiftData + `LiveState`); no JS equivalent.
- **`try XCTUnwrap(x)`** → assert non-null, then use the value.
- **Optionals (`T?`, `.first?`, `?.`, `XCTAssertNil/NotNil`)** → `T | null`, `arr[0]?`, optional chaining, `toBeNull()`/not.
- **Multi-line string `"""…"""`** → a template literal (backticks).
- **Key-path `\.kind`** → `s => s.kind`.
- **`.verse` / `.chorus` (enum shorthand)** → `EnumName.case` with the type inferred.
- **`.count` / `.contains` / `.dropFirst()`** → `.length` / `.includes` / `.slice(1)`.
- **Argument labels (`split(songSections:linesPerSlide:)`)** → modeled as an options object.
- **`Equatable` struct → `XCTAssertEqual` deep compare** → `toEqual` structural equality.
- **`ModelContainer` / `ModelConfiguration` / `ModelContext`** → DB connection / config / session (`// analogy:` an ORM); `isStoredInMemoryOnly: true` → throwaway in-memory DB.
