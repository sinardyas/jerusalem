# `BibleTests.swift`

> Verifies the whole offline Bible pipeline — book-name catalog, reference parser, verse store, and slide splitter — culminating in the Phase 7 gate: typing `John 3:16-18` produces three navigable slides and runs end-to-end under keyboard control.

**Location:** `Tests/JerusalemTests/BibleTests.swift`
**Role:** XCTest unit tests (Phase 7 gate)

## What it does (plain English)
This file guards the path a user takes when they type a scripture reference and expect verses on the screen, with no internet. The data lives in a bundled SwiftData store; the test seeds an in-memory copy and then walks the full chain: *string reference → parsed reference → fetched verses → slide drafts → live program*.

It matters to the "never fail on Sunday morning" promise because Bible lookup must be fully offline and deterministic. A typo or descending range like `John 3:18-16` must fail gracefully (no slides) rather than crash; an unknown book must return nothing; switching between KJV and WEB translations must return genuinely different text.

The last two tests are the actual gate: they build a `bible` `Item`, feed it a reference through `ContentRebuilder`, confirm exactly three slides with the right labels and verse text, then arm a `LiveState` and press "next" three times to prove the operator can run the passage with only the keyboard. All of this is hardware-independent — no window, no AVFoundation.

## XCTest you'll meet in this file
- `final class BibleTests: XCTestCase` — the suite, like `describe('BibleTests', ...)`.
- `func test...() throws` — a test case that may throw; a thrown error fails it (like an async test rejecting).
- `XCTUnwrap(x)` — asserts `x` is non-nil **and** returns the unwrapped value; throws (failing the test) if nil. Used a lot here because `parse(...)` returns an optional.
- `XCTAssertEqual` / `XCTAssertNil` / `XCTAssertNotNil` / `XCTAssertTrue` / `XCTAssertFalse` — the usual `expect(...).toEqual / toBeNull / not null / toBe(true/false)`.
- `XCTAssertGreaterThan(a, b)` — `expect(a).toBeGreaterThan(b)`.
- `@MainActor` — runs the test on the main thread, required because it touches SwiftData (`ModelContext`).
- `ModelConfiguration(isStoredInMemoryOnly: true)` — a throwaway in-memory database per test, like an in-memory SQLite.

## The tests, one by one

### `testCatalogResolvesCanonicalAndAliases`
Feeds `BibleBookCatalog.canonical(for:)` a pile of messy inputs and checks they all normalize to the proper book name: `"jn"`, `"JOHN"`, `" 1 cor "` (with whitespace), `"1cor"`, `"Psalm"` → `"Psalms"`, `"song of songs"` → `"Song of Solomon"`.

```swift
XCTAssertEqual(BibleBookCatalog.canonical(for: " 1 cor "), "1 Corinthians")
XCTAssertEqual(BibleBookCatalog.canonical(for: "song of songs"), "Song of Solomon")
```
**Catches:** a broken alias map or missing case-folding/trim that would make a perfectly valid abbreviation fail to resolve.

### `testCatalogRejectsUnknownBook`
Asserts `canonical(for:)` returns `nil` for `"Hezekiah"` (not a real book) and for the empty string.
**Catches:** the catalog accepting garbage and silently producing a bogus lookup later.

### `testParsesVerseRangeAndWholeChapter`
Parses `"John 3:16-18"` and checks `book == "John"`, `chapter == 3`, `verses == 16...18` (a Swift closed `Range`). Also parses `"Psalm 23"` and confirms the verses field is `nil` — meaning "whole chapter."

```swift
let r1 = try XCTUnwrap(BibleReferenceParser.parse("John 3:16-18"))
XCTAssertEqual(r1.verses, 16...18)
```
**Catches:** off-by-one range parsing, or failing to treat a chapter-only reference as "all verses."

### `testParsesNumberedBookAndSingleVerse`
Parses `"1 Corinthians 13:4"` — a numbered book plus a single verse — and confirms `verses == 4...4` (a single-verse range, not `nil`).
**Catches:** the parser choking on the leading number in book names, or mishandling a lone verse.

### `testParserRejectsMalformedInput`
Confirms `parse(...)` returns `nil` for: empty string, `"John"` (book only, no chapter), `"John three"` (words not digits), `"John 3:18-16"` (a **descending** range), and `"Hezekiah 2:1"` (unknown book).
**Catches:** the parser accepting nonsense or a backwards range that would later produce zero or weird verses without an obvious failure.

### `testReferenceDisplayCanonicalizes`
Checks the `displayText` property cleans up casing/spacing: `"psalm 23"` → `"Psalms 23"`, `"1cor 13:4-7"` → `"1 Corinthians 13:4-7"`, `"john 3:16"` → `"John 3:16"`.
**Catches:** the on-screen reference label showing the user's raw, sloppy input instead of a tidy canonical form.

### `testSeederLoadsStarterDatasetIdempotently`
Uses the private `seededContainer()` helper, which builds an in-memory container and calls `BibleSeeder.seedIfNeeded`. Asserts the verse count is greater than zero, then calls `seedIfNeeded` **again** and asserts the count is unchanged.
```swift
BibleSeeder.seedIfNeeded(context)
XCTAssertEqual(secondCount, firstCount)
```
**Catches:** the seeder duplicating all verses on every launch — which would bloat the store and corrupt lookups.

### `testStoreReturnsVerseRange`
Parses `"John 3:16-18"`, calls `BibleStore.verses(for:translation:in:)` with `"kjv"`, and asserts the returned verse numbers are exactly `[16, 17, 18]`, the book is `"John"`, and the first verse's text is non-empty.
**Catches:** the store returning the wrong verses, an empty slice, or rows with blank text.

### `testStoreReturnsWholeChapter`
Parses `"Psalm 23"` (chapter only) and asserts the store returns verses `1...6` (the starter dataset's Psalm 23 has six verses).
**Catches:** a chapter-only query failing to expand to every verse in the chapter.

### `testStoreReturnsWebTranslationSeparately`
Fetches `John 3:16` in both `"kjv"` and `"web"`, asserts each returns one verse, and crucially that their `text` values are **not equal**.
```swift
XCTAssertNotEqual(kjv.first?.text, web.first?.text)
```
**Catches:** the translation filter being ignored — e.g. always returning KJV regardless of the requested translation.

### `testUnknownReferenceReturnsEmpty`
Parses `"Genesis 1:1"` (Genesis isn't in the starter dataset) and asserts the store returns an empty array — "the store should just shrug."
**Catches:** a missing-book query throwing or returning stale results instead of cleanly returning nothing.

### `testBibleSplitYieldsOneSlidePerVerseWithReferenceFooter`
Fetches `John 3:16-17`, runs `SlideSplitter.split(bibleVerses:translation:)`, and asserts two slide drafts come back with section labels `"John 3:16"` and `"John 3:17"`, and that the first draft's text contains the footer `"— John 3:16 (KJV)"`.
```swift
XCTAssertEqual(drafts[0].sectionLabel, "John 3:16")
XCTAssertTrue(drafts[0].text.contains("— John 3:16 (KJV)"))
```
**Catches:** verses being merged onto one slide, mislabeled slides, or a missing reference/translation footer.

### `testEnterReferenceOfflineRunsThroughKeyboard` (the Phase 7 gate)
The full end-to-end test. Builds a `bible` `Item` with a default theme and `linesPerSlide = 2`, then calls `ContentRebuilder.setBibleReference("John 3:16-18", ...)` as if the user typed it in the editor. Asserts:
- `orderedSlides.count == 3`
- the three section labels are `["John 3:16", "John 3:17", "John 3:18"]`
- the first slide's text contains `"loved the world"` and `"(KJV)"`
- `passage.bibleReference == "John 3:16-18"` (the editor stores back the canonicalized reference)

Then the actual gate — keyboard run-through:
```swift
let live = LiveState()
let program = LiveState.programSlides(for: passage)
live.arm(program)
live.next()
XCTAssertEqual(live.liveSlideID, program[0].id)
live.next()
XCTAssertEqual(live.liveSlideID, program[1].id)
live.next()
XCTAssertEqual(live.liveSlideID, program[2].id)
```
**Catches:** any break in the chain from "user types a reference" to "operator can advance through the verses live" — the single most important Bible-pipeline behavior.

### `testUnknownReferenceClearsSlides`
Builds a passage, sets it to `"John 3:16-18"` (3 slides), then re-points it at `"Genesis 1:1"` (no data) and asserts slides drop to `0`. Then sets a malformed `"not a reference"` and again asserts `0` slides "without crashing."
**Catches:** stale slides lingering when the reference changes to something unresolvable, or a crash on bad input — both of which would leave wrong/old verses on screen Sunday morning.

## How it connects
Exercises `BibleBookCatalog`, `BibleReferenceParser`, `BibleSeeder`, `BibleStore`, `SlideSplitter`, `ContentRebuilder.setBibleReference`, and `LiveState` (`programSlides`, `arm`, `next`, `liveSlideID`), all over an in-memory `ModelContainer` built from `Persistence.schema`. Models touched: `Item` (kind `.bible`), `Slide`, `SlideElement`, `Theme`, `BibleVerse`.

## What it does NOT cover
This is fully programmatic. It does not render the verses to pixels, does not place anything on a real output window, and does not exercise the full-Bible OSIS importer (`Tools/build-bible-db`) — only the bundled starter dataset. Actual on-screen appearance is the renderer's concern, covered elsewhere and ultimately verified by hand on hardware.
