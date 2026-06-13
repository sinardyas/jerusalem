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

**TypeScript equivalent (Jest)**

```ts
expect(BibleBookCatalog.canonical(" 1 cor ")).toEqual("1 Corinthians");
expect(BibleBookCatalog.canonical("song of songs")).toEqual("Song of Solomon");
```

**Swift syntax:**
- `final class BibleTests: XCTestCase` — shape: subclass of `XCTestCase` = a test suite. Jest analog: `describe("BibleTests", () => { … })`.
- `func testCatalogResolvesCanonicalAndAliases()` — shape: `test`-prefixed method = an auto-run test. Jest analog: `it("catalogResolvesCanonicalAndAliases", () => { … })`.
- `BibleBookCatalog.canonical(for: " 1 cor ")` — shape: `for:` is an *argument label* (Swift names arguments at the call site; it's part of the method's full name `canonical(for:)`). Jest analog: just a positional argument — `canonical(" 1 cor ")`.

**Catches:** a broken alias map or missing case-folding/trim that would make a perfectly valid abbreviation fail to resolve.

### `testCatalogRejectsUnknownBook`
Asserts `canonical(for:)` returns `nil` for `"Hezekiah"` (not a real book) and for the empty string.

```swift
XCTAssertNil(BibleBookCatalog.canonical(for: "Hezekiah"))
XCTAssertNil(BibleBookCatalog.canonical(for: ""))
```

**TypeScript equivalent (Jest)**

```ts
// analogy: Swift `nil` ≈ TS null/undefined; canonical() returns string | null.
expect(BibleBookCatalog.canonical("Hezekiah")).toBeNull();
expect(BibleBookCatalog.canonical("")).toBeNull();
```

**Swift syntax:**
- `XCTAssertNil(x)` — shape: passes when `x` is `nil` (Swift's "no value", from an `Optional`). Jest analog: `expect(x).toBeNull()`.

**Catches:** the catalog accepting garbage and silently producing a bogus lookup later.

### `testParsesVerseRangeAndWholeChapter`
Parses `"John 3:16-18"` and checks `book == "John"`, `chapter == 3`, `verses == 16...18` (a Swift closed `Range`). Also parses `"Psalm 23"` and confirms the verses field is `nil` — meaning "whole chapter."

```swift
let r1 = try XCTUnwrap(BibleReferenceParser.parse("John 3:16-18"))
XCTAssertEqual(r1.verses, 16...18)
```

**TypeScript equivalent (Jest)**

```ts
// analogy: Swift `16...18` (ClosedRange) has no native TS type; model it as { lower, upper }.
const r1 = BibleReferenceParser.parse("John 3:16-18");
expect(r1).toBeDefined(); // XCTUnwrap: assert non-null...
const v1 = r1!;           // ...then use the unwrapped value
expect(v1.verses).toEqual({ lower: 16, upper: 18 }); // analogy: 16...18
```

**Swift syntax:**
- `let r1 = try XCTUnwrap(...)` — shape: `XCTUnwrap` asserts the optional is non-nil and *returns the unwrapped value*; combined with `let`, you bind it in one move. `try` is required because it can throw (and the throw fails the test). Jest analog: `expect(x).toBeDefined(); const r1 = x!;`.
- `try` (prefix) — shape: marks a call that can throw an error; in a `throws` test an uncaught throw fails the test. Jest analog: `await`-ing a promise that may reject.
- `16...18` — shape: a `ClosedRange<Int>` literal (both ends inclusive). Jest analog: no direct equivalent; modeled here as `{ lower, upper }` or an array `[16,17,18]`.

**Catches:** off-by-one range parsing, or failing to treat a chapter-only reference as "all verses."

### `testParsesNumberedBookAndSingleVerse`
Parses `"1 Corinthians 13:4"` — a numbered book plus a single verse — and confirms `verses == 4...4` (a single-verse range, not `nil`).

```swift
let r = try XCTUnwrap(BibleReferenceParser.parse("1 Corinthians 13:4"))
XCTAssertEqual(r.book, "1 Corinthians")
XCTAssertEqual(r.chapter, 13)
XCTAssertEqual(r.verses, 4...4)
```

**TypeScript equivalent (Jest)**

```ts
const r = BibleReferenceParser.parse("1 Corinthians 13:4");
expect(r).toBeDefined();
const v = r!;
expect(v.book).toEqual("1 Corinthians");
expect(v.chapter).toEqual(13);
expect(v.verses).toEqual({ lower: 4, upper: 4 }); // analogy: 4...4, a single-verse range
```

**Catches:** the parser choking on the leading number in book names, or mishandling a lone verse.

### `testParserRejectsMalformedInput`
Confirms `parse(...)` returns `nil` for: empty string, `"John"` (book only, no chapter), `"John three"` (words not digits), `"John 3:18-16"` (a **descending** range), and `"Hezekiah 2:1"` (unknown book).

```swift
XCTAssertNil(BibleReferenceParser.parse(""))
XCTAssertNil(BibleReferenceParser.parse("John"))
XCTAssertNil(BibleReferenceParser.parse("John three"))
XCTAssertNil(BibleReferenceParser.parse("John 3:18-16"))  // descending range
XCTAssertNil(BibleReferenceParser.parse("Hezekiah 2:1"))
```

**TypeScript equivalent (Jest)**

```ts
expect(BibleReferenceParser.parse("")).toBeNull();
expect(BibleReferenceParser.parse("John")).toBeNull();
expect(BibleReferenceParser.parse("John three")).toBeNull();
expect(BibleReferenceParser.parse("John 3:18-16")).toBeNull(); // descending range
expect(BibleReferenceParser.parse("Hezekiah 2:1")).toBeNull();
```

**Catches:** the parser accepting nonsense or a backwards range that would later produce zero or weird verses without an obvious failure.

### `testReferenceDisplayCanonicalizes`
Checks the `displayText` property cleans up casing/spacing: `"psalm 23"` → `"Psalms 23"`, `"1cor 13:4-7"` → `"1 Corinthians 13:4-7"`, `"john 3:16"` → `"John 3:16"`.

```swift
XCTAssertEqual(BibleReferenceParser.parse("psalm 23")?.displayText, "Psalms 23")
XCTAssertEqual(BibleReferenceParser.parse("1cor 13:4-7")?.displayText, "1 Corinthians 13:4-7")
XCTAssertEqual(BibleReferenceParser.parse("john 3:16")?.displayText, "John 3:16")
```

**TypeScript equivalent (Jest)**

```ts
// analogy: Swift `?.` (optional chaining) is the same `?.` in TS.
expect(BibleReferenceParser.parse("psalm 23")?.displayText).toEqual("Psalms 23");
expect(BibleReferenceParser.parse("1cor 13:4-7")?.displayText).toEqual("1 Corinthians 13:4-7");
expect(BibleReferenceParser.parse("john 3:16")?.displayText).toEqual("John 3:16");
```

**Swift syntax:**
- `parse(...)?.displayText` — shape: `?.` is *optional chaining* — if `parse(...)` returns `nil`, the whole expression is `nil`; otherwise it reads `.displayText`. Jest analog: identical `?.` operator in TS/JS.

**Catches:** the on-screen reference label showing the user's raw, sloppy input instead of a tidy canonical form.

### `testSeederLoadsStarterDatasetIdempotently`
Uses the private `seededContainer()` helper, which builds an in-memory container and calls `BibleSeeder.seedIfNeeded`. Asserts the verse count is greater than zero, then calls `seedIfNeeded` **again** and asserts the count is unchanged.
```swift
BibleSeeder.seedIfNeeded(context)
XCTAssertEqual(secondCount, firstCount)
```

**TypeScript equivalent (Jest)**

```ts
// analogy: in-memory SwiftData container ≈ a fresh in-memory test DB (like better-sqlite3 :memory:).
BibleSeeder.seedIfNeeded(context);
expect(secondCount).toEqual(firstCount); // idempotent: second seed changes nothing
```

**Swift syntax:**
- `@MainActor private func seededContainer() throws -> ModelContainer` — shape: a `private` helper marked `@MainActor` (runs on the main thread) that may `throw` and returns a `ModelContainer`. Jest analog: a local `async function seededContainer()` factory used by tests.
- `ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))` — shape: builds an in-memory SwiftData store from a schema. `// analogy:` an in-memory SQLite DB created per test (like `better-sqlite3` `:memory:`).
- `XCTAssertGreaterThan(firstCount, 0, "…")` — shape: ordered comparison assert; the trailing string is a failure message. Jest analog: `expect(firstCount).toBeGreaterThan(0)`.
- `try? context.fetchCount(...) ?? 0` — shape: `try?` turns a throwing call into an optional (`nil` on error), and `??` supplies a default. Jest analog: `(maybeThrow() ?? 0)` after swallowing the error.

**Catches:** the seeder duplicating all verses on every launch — which would bloat the store and corrupt lookups.

### `testStoreReturnsVerseRange`
Parses `"John 3:16-18"`, calls `BibleStore.verses(for:translation:in:)` with `"kjv"`, and asserts the returned verse numbers are exactly `[16, 17, 18]`, the book is `"John"`, and the first verse's text is non-empty.

```swift
let verses = BibleStore.verses(for: reference, translation: "kjv", in: context)
XCTAssertEqual(verses.map(\.number), [16, 17, 18])
XCTAssertEqual(verses.first?.book, "John")
XCTAssertFalse(verses.first?.text.isEmpty ?? true)
```

**TypeScript equivalent (Jest)**

```ts
const verses = BibleStore.verses(reference, "kjv", context);
// analogy: Swift `\.number` is a key path; .map(\.number) === .map(v => v.number).
expect(verses.map((v) => v.number)).toEqual([16, 17, 18]);
expect(verses[0]?.book).toEqual("John");
expect((verses[0]?.text.length ?? 0) > 0).toBe(true); // .text.isEmpty == false
```

**Swift syntax:**
- `.map(\.number)` — shape: `\.number` is a *key path* — shorthand for the closure `{ $0.number }`. Jest analog: `.map(v => v.number)`.
- `verses.first?.book` — shape: `.first` returns an `Optional` (the array may be empty), so `?.` is needed. Jest analog: `verses[0]?.book`.
- `verses.first?.text.isEmpty ?? true` — shape: `??` is the *nil-coalescing* operator — "use the left value, or `true` if it's `nil`." Jest analog: `?? true` (nullish coalescing).
- `XCTAssertFalse(x)` — shape: passes when `x` is `false`. Jest analog: `expect(x).toBe(false)`.

**Catches:** the store returning the wrong verses, an empty slice, or rows with blank text.

### `testStoreReturnsWholeChapter`
Parses `"Psalm 23"` (chapter only) and asserts the store returns verses `1...6` (the starter dataset's Psalm 23 has six verses).

```swift
let verses = BibleStore.verses(for: reference, translation: "kjv", in: context)
XCTAssertEqual(verses.map(\.number), Array(1...6))
```

**TypeScript equivalent (Jest)**

```ts
const verses = BibleStore.verses(reference, "kjv", context);
// analogy: Array(1...6) builds [1,2,3,4,5,6]; here we spell it out.
expect(verses.map((v) => v.number)).toEqual([1, 2, 3, 4, 5, 6]);
```

**Swift syntax:**
- `Array(1...6)` — shape: builds `[1,2,3,4,5,6]` by materializing a `ClosedRange` into an array. Jest analog: `[1,2,3,4,5,6]` (or `Array.from({length:6},(_,i)=>i+1)`).

**Catches:** a chapter-only query failing to expand to every verse in the chapter.

### `testStoreReturnsWebTranslationSeparately`
Fetches `John 3:16` in both `"kjv"` and `"web"`, asserts each returns one verse, and crucially that their `text` values are **not equal**.
```swift
XCTAssertNotEqual(kjv.first?.text, web.first?.text)
```

**TypeScript equivalent (Jest)**

```ts
const kjv = BibleStore.verses(reference, "kjv", context);
const web = BibleStore.verses(reference, "web", context);
expect(kjv.length).toEqual(1);
expect(web.length).toEqual(1);
expect(kjv[0]?.text).not.toEqual(web[0]?.text);
```

**Swift syntax:**
- `XCTAssertNotEqual(a, b)` — shape: passes when `a != b`. Jest analog: `expect(a).not.toEqual(b)`.

**Catches:** the translation filter being ignored — e.g. always returning KJV regardless of the requested translation.

### `testUnknownReferenceReturnsEmpty`
Parses `"Genesis 1:1"` (Genesis isn't in the starter dataset) and asserts the store returns an empty array — "the store should just shrug."

```swift
XCTAssertTrue(BibleStore.verses(for: reference, translation: "kjv", in: context).isEmpty)
```

**TypeScript equivalent (Jest)**

```ts
// analogy: Swift `.isEmpty` ≈ `arr.length === 0`.
expect(BibleStore.verses(reference, "kjv", context).length).toBe(0);
```

**Catches:** a missing-book query throwing or returning stale results instead of cleanly returning nothing.

### `testBibleSplitYieldsOneSlidePerVerseWithReferenceFooter`
Fetches `John 3:16-17`, runs `SlideSplitter.split(bibleVerses:translation:)`, and asserts two slide drafts come back with section labels `"John 3:16"` and `"John 3:17"`, and that the first draft's text contains the footer `"— John 3:16 (KJV)"`.
```swift
XCTAssertEqual(drafts[0].sectionLabel, "John 3:16")
XCTAssertTrue(drafts[0].text.contains("— John 3:16 (KJV)"))
```

**TypeScript equivalent (Jest)**

```ts
const drafts = SlideSplitter.split(verses, "kjv");
expect(drafts.length).toEqual(2);
expect(drafts[0].sectionLabel).toEqual("John 3:16");
expect(drafts[1].sectionLabel).toEqual("John 3:17");
// analogy: Swift String.contains(...) ≈ JS String.includes(...).
expect(drafts[0].text.includes("— John 3:16 (KJV)")).toBe(true);
```

**Swift syntax:**
- `drafts[0].text.contains("…")` — shape: `String.contains` is substring containment. Jest analog: `str.includes("…")`.
- `XCTAssertTrue(x)` — shape: passes when `x` is `true`. Jest analog: `expect(x).toBe(true)`.

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

**TypeScript equivalent (Jest)**

```ts
const live = new LiveState();
const program = LiveState.programSlides(passage);
live.arm(program);
live.next();
expect(live.liveSlideID).toEqual(program[0].id);
live.next();
expect(live.liveSlideID).toEqual(program[1].id);
live.next();
expect(live.liveSlideID).toEqual(program[2].id);
```

**Catches:** any break in the chain from "user types a reference" to "operator can advance through the verses live" — the single most important Bible-pipeline behavior.

### `testUnknownReferenceClearsSlides`
Builds a passage, sets it to `"John 3:16-18"` (3 slides), then re-points it at `"Genesis 1:1"` (no data) and asserts slides drop to `0`. Then sets a malformed `"not a reference"` and again asserts `0` slides "without crashing."

```swift
ContentRebuilder.setBibleReference("John 3:16-18", translation: "kjv", on: passage)
XCTAssertEqual(passage.orderedSlides.count, 3)
ContentRebuilder.setBibleReference("Genesis 1:1", translation: "kjv", on: passage)
XCTAssertEqual(passage.orderedSlides.count, 0)
ContentRebuilder.setBibleReference("not a reference", translation: "kjv", on: passage)
XCTAssertEqual(passage.orderedSlides.count, 0)
```

**TypeScript equivalent (Jest)**

```ts
ContentRebuilder.setBibleReference("John 3:16-18", "kjv", passage);
expect(passage.orderedSlides.length).toEqual(3);
ContentRebuilder.setBibleReference("Genesis 1:1", "kjv", passage); // no data → clears
expect(passage.orderedSlides.length).toEqual(0);
ContentRebuilder.setBibleReference("not a reference", "kjv", passage); // malformed → clears, no throw
expect(passage.orderedSlides.length).toEqual(0);
```

**Catches:** stale slides lingering when the reference changes to something unresolvable, or a crash on bad input — both of which would leave wrong/old verses on screen Sunday morning.

## How it connects
Exercises `BibleBookCatalog`, `BibleReferenceParser`, `BibleSeeder`, `BibleStore`, `SlideSplitter`, `ContentRebuilder.setBibleReference`, and `LiveState` (`programSlides`, `arm`, `next`, `liveSlideID`), all over an in-memory `ModelContainer` built from `Persistence.schema`. Models touched: `Item` (kind `.bible`), `Slide`, `SlideElement`, `Theme`, `BibleVerse`.

## What it does NOT cover
This is fully programmatic. It does not render the verses to pixels, does not place anything on a real output window, and does not exercise the full-Bible OSIS importer (`Tools/build-bible-db`) — only the bundled starter dataset. Actual on-screen appearance is the renderer's concern, covered elsewhere and ultimately verified by hand on hardware.

## XCTest → Jest glossary
- `final class X: XCTestCase { }` — shape: subclass = test suite. Jest analog: `describe("X", () => { … })`.
- `func testFoo() throws` — shape: `test`-prefixed, `throws`-able method; an uncaught throw fails it. Jest analog: an `async`/throwing `it("foo", async () => { … })`.
- `@MainActor` — shape: forces the test onto the main thread (here because SwiftData's `ModelContext` is main-thread bound). Jest analog: `// runs on the main thread` (no real equivalent; Jest is single-threaded already).
- `XCTUnwrap(x)` — shape: assert non-nil **and** return the unwrapped value (throws if nil). Jest analog: `expect(x).toBeDefined(); const v = x!;`.
- `XCTAssertEqual / XCTAssertNotEqual(a, b)` — Jest: `expect(a).toEqual(b)` / `.not.toEqual(b)`.
- `XCTAssertNil / XCTAssertNotNil(x)` — Jest: `expect(x).toBeNull()` / `.not.toBeNull()`.
- `XCTAssertTrue / XCTAssertFalse(x)` — Jest: `expect(x).toBe(true)` / `.toBe(false)`.
- `XCTAssertGreaterThan(a, b)` — Jest: `expect(a).toBeGreaterThan(b)`.
- `ModelConfiguration(isStoredInMemoryOnly: true)` — shape: throwaway in-memory SwiftData store. `// analogy:` an in-memory SQLite test DB (`:memory:`).
- `\.number` (key path) / `.map(\.number)` — shape: property shorthand closure. Jest analog: `.map(v => v.number)`.
- `?.` / `??` — shape: optional chaining / nil-coalescing. Jest analog: identical `?.` / `??`.
- `a...b` — shape: an inclusive `ClosedRange`. Jest analog: no direct type; modeled as a `{ lower, upper }` object or an array.
