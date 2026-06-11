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

### `testMarkersAreCaseInsensitive`
`[VERSE 2]` and `[ chorus ]` (note the spaces and caps) still parse to `.verse` / `.chorus`. Catches a too-strict marker regex.

### `testBareLyricsBecomeASingleVerse`
Lyrics with *no* markers become one unnumbered `.verse`. Catches an empty result when the user doesn't use markers.

### `testUnknownBracketLineIsNotAMarker`
`[Refrain]` isn't in the MVP marker vocabulary, so it must **not** split a section — it's kept as literal content. Catches an unknown bracket silently eating a line or starting a phantom section.

```swift
XCTAssertEqual(sections.count, 1)
XCTAssertTrue(sections[0].lyrics.contains("[Refrain]"))
```

### `testFormatRoundTripsBackThroughParser`
`SongLyricsParser.format(sections)` produces text that parses back to the *same* sections. Proves parse/format are inverses (so the editor can round-trip the authored text). Catches formatting that drifts from the parser's grammar.

### `testSplitterHonorsLinesPerSlide`
Five lines at `linesPerSlide: 2` → three slide drafts: `["l1\nl2", "l3\nl4", "l5"]`. Catches the wrong chunking or a dropped trailing line.

### `testOnlyFirstSlideOfSectionGetsTheLabel`
Only the first draft of a section carries `sectionLabel == "Verse 1"`; subsequent drafts have `nil`. This keeps "Verse 1" from repeating on every continuation slide.

### `testSermonSplitProducesTitleAndPointSlides`
A sermon split yields a `"Title"` slide (the sermon title) followed by `"Point 1"`, `"Point 2"`, `"Point 3"` from blank-line-separated paragraphs. Catches sermon structure being mislabeled.

### `testEditingLyricsRebuildsSlidesAndDrivesLiveProgram` `@MainActor throws`
The actual gate. It sets full "Amazing Grace" lyrics on a song (two verse lines + a chorus), expects exactly 3 slides with labels `["Verse 1", nil, "Chorus"]` and the correct first-slide text. Then it builds a `LiveState`, arms the program via `LiveState.programSlides(for: song)`, and presses `next()` three times, asserting `liveSlideID` lands on slides 0, 1, 2 in turn — a full keyboard run-through.

```swift
live.arm(program)
live.next()                              // first press starts at slide 0
XCTAssertEqual(live.liveSlideID, program[0].id)
```

### `testChangingLinesPerSlideRebuildsWithoutLosingLyrics` `@MainActor throws`
Four lines at `linesPerSlide: 4` → 1 slide; change to `2` and rebuild → 2 slides. Crucially, the original lyrics still live in `orderedSongSections.first?.lyrics` unchanged. This is the payoff of keeping `SongSection` rows as the source of truth — re-splitting is non-destructive.

### `testSermonRebuildProducesTitleThenPoints` `@MainActor throws`
`ContentRebuilder.setBody` on a `.text` item produces slides labeled `["Title", "Point 1", "Point 2", "Point 3"]`, with the title slide carrying the item title text. The rebuilder equivalent of the splitter sermon test.

### `testRebuiltSlideUsesItemTheme` `@MainActor throws`
A rebuilt slide inherits its item's `Theme` — background `#112233`, font `Helvetica` at `64`, text color `#ABCDEF` — confirming the theme is applied during materialization, not hard-coded.

## How it connects

Exercises `SongLyricsParser` (parse/format), `ParsedSongSection`, `SlideSplitter` (`split(songSections:...)` and `split(sermonTitle:body:...)`), `ContentRebuilder` (`setLyrics`, `setBody`, `rebuild`), the SwiftData models `Item` / `Slide` / `SlideElement` / `SongSection` / `Theme`, and `LiveState` (`programSlides`, `arm`, `next`, `liveSlideID`).

## What it does NOT cover

Every assertion is pure logic, SwiftData, or `LiveState` — no AppKit window, no AVFoundation. The actual on-screen appearance of the slides and the operator's live experience are verified by running the app.
