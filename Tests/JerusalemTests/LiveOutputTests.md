# `LiveOutputTests.swift`

> Pins down the two programmatic guarantees behind Phase 3 output: live content is an immutable snapshot (editing the model can't change what's on screen), and `ScreenSelection.outputIndex` picks the right display.

**Location:** `Tests/JerusalemTests/LiveOutputTests.swift`
**Role:** XCTest unit tests (Phase 3 gate — the programmatic parts only)

## What it does (plain English)
Phase 3 is dual-screen live output. The riskiest, hardware-dependent parts of that (full-screen `NSWindow` placement, surviving a display unplug/replug) can only be verified by hand. What *can* be tested headlessly are the two pure rules underneath, and that's exactly what this file does.

First, the **edit/live separation invariant**: when you go live, `LiveState` holds an immutable *value snapshot* of the slide, not the live SwiftData `@Model`. So if the operator edits the underlying song while it's on the audience screen, the screen must not change until they explicitly re-arm/advance. This is core to "never fail on Sunday morning" — you can prep the next edit without flickering the current output.

Second, `ScreenSelection.outputIndex` — the pure function that decides *which* `NSScreen` the audience output goes on (prefer a non-main display). The function is tested; the actual window placement on that screen is not.

## XCTest you'll meet in this file
- `final class LiveOutputTests: XCTestCase` — the suite.
- `@MainActor` — main-thread tests (SwiftData + `LiveState`).
- `XCTAssertEqual` / `XCTAssertNil` — `expect(...).toEqual / toBeNull`.
- `XCTFail("msg")` — force a failure, used in the `guard case` fallthrough.
- `guard case .slide(let renderable) = live.content else { return XCTFail(...) }` — enum pattern match that binds the `.slide` payload or fails (like switching on a tagged union's type and grabbing its data).
- `try!` — force-try in setup, assumed not to throw.

## The `makeItem` helper
A private `@MainActor` helper inserts a one-slide `song` `Item` (with a single text element) into a given context and returns it — keeping each test's setup to one line.

```swift
@MainActor
private func makeItem(_ context: ModelContext, text: String) -> Item {
    let item = Item(kind: .song, title: "Song")
    let slide = Slide(order: 0, sectionLabel: "V1")
    slide.elements = [SlideElement(kind: .text, text: text)]
    item.slides.append(slide)
    context.insert(item)
    return item
}
```

**TypeScript equivalent (Jest)**

```ts
function makeItem(context: ModelContext, text: string): Item {
  const item = new Item({ kind: "song", title: "Song" });
  const slide = new Slide({ order: 0, sectionLabel: "V1" });
  slide.elements = [new SlideElement({ kind: "text", text })];
  item.slides.push(slide);
  context.insert(item);
  return item;
}
```

**Swift syntax:**
- `private func makeItem(_ context: ModelContext, text: String) -> Item` — shape: the `_` before `context` means *no argument label* (call it positionally: `makeItem(ctx, text: "…")`), while `text:` keeps its label. Jest analog: `makeItem(context, text)` — all positional.
- `@MainActor` — shape: pins this code to the main thread (SwiftData's context is main-thread bound). Jest analog: `// runs on the main thread`.

## The tests, one by one

### `testLiveContentIsASnapshotUnaffectedByModelEdits`
Builds an item whose slide text is `"original"`, arms it, goes live (`next()`), then **mutates the underlying model** to `"EDITED"`. It then asserts the live content still reads `"original"`.
```swift
item.orderedSlides.first?.orderedElements.first?.text = "EDITED"

guard case .slide(let renderable) = live.content else {
    return XCTFail("expected a live slide")
}
XCTAssertEqual(renderable.elements.first?.text, "original")
```

**TypeScript equivalent (Jest)**

```ts
// Mutate the live @Model after going live — the snapshot must not change.
item.orderedSlides[0]?.orderedElements[0] && (item.orderedSlides[0].orderedElements[0].text = "EDITED");

// analogy: `guard case .slide(let renderable)` ≈ narrowing a discriminated union by its tag.
if (live.content.type !== "slide") {
  throw new Error("expected a live slide"); // XCTFail
}
const renderable = live.content.renderable;
expect(renderable.elements[0]?.text).toEqual("original"); // frozen snapshot, not "EDITED"
```

**Swift syntax:**
- `item.orderedSlides.first?.orderedElements.first?.text = "EDITED"` — shape: chained `?.` optional access used on the *left* of an assignment — if any link is `nil` the write is silently skipped. Jest analog: guarded assignment (TS has no optional-chained assignment, so you check first).
- `guard case .slide(let renderable) = live.content else { return XCTFail("…") }` — shape: pattern-match the `.slide` enum case, binding its payload to `renderable`; otherwise fail and exit. Jest analog: narrow a discriminated union by `type`, else `throw`.

**Catches:** the single most dangerous regression in the app — the live output reading directly from the editable `@Model` instead of a frozen snapshot. If that broke, an in-progress edit (or an autosave) could change the audience screen mid-service.

### `testClearResetsOutput`
Arms an item, goes live, then calls `clear()`. Asserts `content == .empty` and `liveSlideID == nil`.
```swift
live.clear()
XCTAssertEqual(live.content, .empty)
XCTAssertNil(live.liveSlideID)
```

**TypeScript equivalent (Jest)**

```ts
live.clear();
expect(live.content).toEqual({ type: "empty" }); // analogy: enum case .empty
expect(live.liveSlideID).toBeNull();
```

**Catches:** the Clear action leaving stale content or a dangling "current slide" id.

### `testOutputScreenPrefersNonMainDisplay`
Pure-function table test for `ScreenSelection.outputIndex(screenCount:mainIndex:)`:
```swift
XCTAssertEqual(ScreenSelection.outputIndex(screenCount: 1, mainIndex: 0), 0)
XCTAssertEqual(ScreenSelection.outputIndex(screenCount: 2, mainIndex: 0), 1)
XCTAssertEqual(ScreenSelection.outputIndex(screenCount: 2, mainIndex: 1), 0)
XCTAssertEqual(ScreenSelection.outputIndex(screenCount: 3, mainIndex: 1), 0)
```

**TypeScript equivalent (Jest)**

```ts
expect(ScreenSelection.outputIndex(1, 0)).toEqual(0);
expect(ScreenSelection.outputIndex(2, 0)).toEqual(1);
expect(ScreenSelection.outputIndex(2, 1)).toEqual(0);
expect(ScreenSelection.outputIndex(3, 1)).toEqual(0);
```

With one screen there's nowhere else to go, so it returns `0` (the operator preview). With two or more, it picks a screen that isn't the main one (where the operator window lives), so the audience output lands on the projector/TV.
**Catches:** the app putting the audience output on the operator's own laptop screen, or crashing/returning an out-of-range index when there's only one display.

## How it connects
Exercises `LiveState` (`arm`, `next`, `clear`, `content`, `liveSlideID`, `programSlides`), the `LiveState.Content` enum, `RenderableSlide` (the immutable snapshot), and `ScreenSelection.outputIndex` (a pure caseless-enum namespace function). Models touched: `Item`, `Slide`, `SlideElement` in an in-memory `ModelContainer`.

## What it does NOT cover
The hardware-dependent half of Phase 3. There's no real `NSWindow`, no full-screen placement on an external display, and no display unplug/replug fail-over. `ScreenSelection.outputIndex` is the *pure rule* that is tested; `OutputController` actually moving the window to that screen, and surviving `didChangeScreenParameters`, must be verified by running the app with a second display attached.

## XCTest → Jest glossary
- `final class X: XCTestCase { }` — shape: subclass = test suite. Jest: `describe("X", () => { … })`.
- `func testFoo()` — shape: `test`-prefixed, auto-run. Jest: `it("foo", () => { … })`.
- `@MainActor` — shape: run on the main thread (here for SwiftData + `LiveState`). Jest: `// runs on the main thread`.
- `XCTAssertEqual(a, b)` — Jest: `expect(a).toEqual(b)`.
- `XCTAssertNil(x)` — Jest: `expect(x).toBeNull()`.
- `XCTFail("m")` — shape: unconditionally fail. Jest: `throw new Error("m")`.
- `try!` — shape: force-try, crash on throw. Jest: an unguarded call expected to succeed.
- `guard case .slide(let x) = value else { … }` — shape: match an enum case + bind its payload, else exit. Jest: narrow a discriminated union by `type`, else `throw`.
- `enum` + leading-dot case (`.empty`, `.slide(...)`) — shape: tagged union. Jest: `{ type: "empty" }` / `{ type: "slide", renderable }`.
- `?.` (optional chaining, incl. on the LHS) — shape: nil-safe access. Jest: `?.` (read only; guard before assigning).
- `_` argument label — shape: no call-site label (positional). Jest: a plain positional parameter.
- `ModelConfiguration(isStoredInMemoryOnly: true)` — shape: throwaway in-memory store. `// analogy:` in-memory SQLite (`:memory:`).
