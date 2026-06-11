# `LiveNavigationTests.swift`

> Verifies the operator can run a program entirely by keyboard — arm, next/previous (with start and end clamping), go-live-by-id, the Black/Clear panic states — plus the library search rules.

**Location:** `Tests/JerusalemTests/LiveNavigationTests.swift`
**Role:** XCTest unit tests (Phase 4 gate — the navigation *logic*)

## What it does (plain English)
Phase 4 is "run a service without the mouse." This file is the logic half of that gate: it drives a `LiveState` the way the keyboard monitor would (space/arrows to advance, B/C to panic) and asserts the live output state lands where it should. No AppKit window is involved — it checks `LiveState`'s in-memory state, which the real output window merely mirrors.

The behaviors here are the ones that bite hardest live: a first "next" must *start* the program (not skip the first slide), pressing past the end must *clamp* rather than crash or blank, "Black" must hide everything and then *resume* on the next nav key, and "Clear" must keep the background but drop the text. Getting any of these wrong is a visible on-screen mistake during worship.

It also covers `LibrarySearch`, the pure matching rule behind the search box — title matching, multi-word content matching across lines, and the rule that *every* query word must be present. Search is how the operator finds the next song fast under pressure, so its rules are pinned down here.

## XCTest you'll meet in this file
- `final class LiveNavigationTests: XCTestCase` — the suite (`describe(...)`).
- `func testXxx()` — a test case (`it(...)`); the method name is the test name.
- `@MainActor` on the SwiftData-touching tests — run on the main thread (needed for `ModelContext`).
- `XCTAssertEqual` / `XCTAssertNil` / `XCTAssertTrue` / `XCTAssertFalse` — standard `expect(...)` equivalents.
- `XCTFail("msg")` — force a failure; used inside `guard case` when a pattern match doesn't hold.
- `guard case .slide(let renderable) = live.content else { return XCTFail(...) }` — Swift enum pattern matching: "if `content` is the `.slide` case, bind its associated value to `renderable`, otherwise fail." Like checking a tagged union's `type` and pulling out its payload.
- `try!` — force-try; crashes if it throws. Used in the test helper where setup is assumed safe.

## The `makeProgram` helper
A private `@MainActor` helper builds a real in-memory `Item` with `slideCount` slides (each with a text element unless `withText: false`), saves it, and returns `LiveState.programSlides(for:)` — an array of immutable `ProgramSlide` value snapshots. The comment notes these snapshots are independent of the container, so the container can deallocate without affecting them — this is the edit/live separation invariant in action.

## The tests, one by one

### `testArmDoesNotChangeOutput`
Arms a 3-slide program and asserts `live.content == .empty` and `live.liveSlideID == nil`.
```swift
live.arm(makeProgram(slideCount: 3))
XCTAssertEqual(live.content, .empty)
XCTAssertNil(live.liveSlideID)
```
**Catches:** arming (loading) a program accidentally pushing slide 1 to the audience screen. Arming must be silent — you load the next song while the current one is still showing.

### `testNextStartsAdvancesAndClamps`
Arms 3 slides, then presses `next()` repeatedly. First press lands on `program[0]` (it *starts*, not skips), subsequent presses advance to `[1]` then `[2]`, and a fourth press stays on `[2]` (clamps at the end). Then `previous()` steps back to `[1]`.
```swift
live.next()
XCTAssertEqual(live.liveSlideID, program[0].id)   // first press starts at 0
...
live.next()
XCTAssertEqual(live.liveSlideID, program[2].id)   // clamps at the end
```
**Catches:** off-by-one navigation, the classic "first arrow press skips the opening slide," or running off the end into a crash/blank.

### `testGoLiveByID`
Arms 3 slides and calls `goLive(id: program[2].id)` to jump straight to the last slide; asserts `liveSlideID` is now that id.
**Catches:** click-to-go-live (jumping by id, e.g. from the grid) landing on the wrong slide.

### `testBlackPanicThenResume`
Arms 2 slides, advances to slide 0, then `setPanic(.black)`. Asserts `content == .black` and `liveSlideID == nil` (no slide is "current" while blacked). Then a `next()` resumes the program back at `program[0]`.
```swift
live.setPanic(.black)
XCTAssertEqual(live.content, .black)
XCTAssertNil(live.liveSlideID)
live.next()                                       // nav key resumes
XCTAssertEqual(live.liveSlideID, program[0].id)
```
**Catches:** the panic Black button failing to blank the screen, or getting stuck black with no way to resume — both nightmare scenarios live.

### `testClearShowsBackgroundOnly`
Arms 1 slide with text, advances to it, then `setPanic(.clear)`. Pattern-matches that `content` is still a `.slide` (background intact) but its `elements` array is empty (text gone).
```swift
guard case .slide(let renderable) = live.content else {
    return XCTFail("expected a background-only slide")
}
XCTAssertTrue(renderable.elements.isEmpty)
```
**Catches:** "Clear" wiping the whole screen instead of just the text, or doing nothing.

### `testSearchMatching`
Tests `LibrarySearch.matches(title:query:)`: empty query matches, `"grace"` matches `"Amazing Grace"` (substring), `"AMAZING"` matches (case-insensitive), `"psalm"` does not.
**Catches:** case-sensitive or non-substring title search.

### `testContentSearchMatching`
Tests `LibrarySearch.matches(query:in:)` against multi-line lyric text. Empty/whitespace queries match everything; a single word like `"WRETCH"` matches case-insensitively; multi-word queries like `"sweet grace"` match when *all* words appear (even across different lines, any order); but `"grace mercy"` fails because `"mercy"` is absent.
```swift
XCTAssertTrue(LibrarySearch.matches(query: "sweet grace", in: text))
XCTAssertFalse(LibrarySearch.matches(query: "grace mercy", in: text))
```
**Catches:** AND-vs-OR search bugs — a search that returns matches when only *some* words are present would flood the operator with wrong results.

### `testSearchableTextIncludesSlideContent`
Builds an in-memory `Item` with a title, subtitle, a slide section label, and slide text, then queries its `searchableText`. Confirms the title (`"newton"` from the subtitle), the section label (`"verse"`), and the slide body (`"sweet sound"`) are all searchable, while an absent word (`"wretch"`) is not.
**Catches:** search indexing only the title and missing lyrics/labels — meaning you couldn't find a song by a line you remember.

## How it connects
Exercises `LiveState` (`arm`, `next`, `previous`, `goLive`, `setPanic`, `clear`, `content`, `liveSlideID`, `programSlides`), the `LiveState.Content` enum (`.empty` / `.black` / `.slide`), `RenderableSlide` (the value snapshot), and `LibrarySearch`. Models touched: `Item`, `Slide`, `SlideElement`, all in an in-memory `ModelContainer` from `Persistence.schema`.

## What it does NOT cover
The actual on-screen result. `LiveState` here is checked as pure state; the real `OutputController`/`NSWindow` that displays `content`, and the keyboard `NSEvent` monitor in `OperatorView` that calls these methods, are not exercised. Whether the audience screen visibly goes black, or whether key presses are wired correctly, is verified by running the app on hardware.
