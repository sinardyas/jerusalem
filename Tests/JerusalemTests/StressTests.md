# `StressTests.swift`

> The Phase 9 soak fixture: builds a synthetic service-sized playlist (songs + missing-file videos), walks it end-to-end through `LiveState` hundreds of times, proves program snapshots survive their database being dropped, and checks the slide prewarmer's cache stays bounded.

**Location:** `Tests/JerusalemTests/StressTests.swift`
**Role:** XCTest unit tests

## What it does (plain English)

The product promise is "never fail on Sunday morning." This file is the headless stress test for that promise: feed the engine a realistically large, deliberately messy program and mash the navigation buttons far past the ends to flush out crashes, off-by-one clamps, or stale-state bugs.

A private helper, `makeServicePlaylist`, builds an in-memory playlist of 10 songs (8 slides each) plus 4 video items whose files are **intentionally missing on disk** — so the missing-media fallback path is exercised too. Then the tests:

- arm that program in `LiveState` and call `next()` 200 times and `previous()` 200 times, asserting the navigator never bottoms out into an empty state and clamps cleanly at both ends;
- snapshot a song into a value-type program, **drop the SwiftData container**, and prove the live output still has intact content (the edit/live separation invariant — snapshots are values, not live model references);
- hammer the `SlidePrewarmer` LRU cache with more entries than its limit and confirm it evicts down to the cap, and that a cache hit returns the *same* image instance.

## XCTest you'll meet in this file

| XCTest API | Jest equivalent |
| --- | --- |
| `func testFoo() throws` | `it('foo', ...)` that fails on throw |
| `XCTAssertEqual / NotEqual(a, b, "msg")` | `expect(a).toEqual/not.toEqual(b)` |
| `XCTAssertLessThanOrEqual(a, b)` | `expect(a).toBeLessThanOrEqual(b)` |
| `XCTAssertNotNil(x)` | `expect(x).not.toBeNull()` |
| `XCTAssertTrue(first === cached)` | `expect(first).toBe(cached)` — reference identity (same object) |
| `XCTFail("msg")` | `throw new Error('msg')` / forced fail in an unexpected branch |
| `@MainActor` | runs on the main thread (SwiftData, `LiveState`, prewarmer) |
| `if case .slide(let x) = ...` | pattern-match a tagged-union/enum case and bind its payload |

## The tests, one by one

### `testServiceSizedProgramAdvancesWithoutCrash` `@MainActor throws`
Builds the soak playlist, snapshots it via `LiveState.programSlides(for: playlist)`, and asserts the program length is `10 * 8 + 4 == 84` items. Arms it, then calls `next()` 200 times — far past the 84th slide — asserting after every press that `live.content != .empty` (the navigator must clamp at the end, never fall into nothing). Then `previous()` 200 times and asserts it lands back on the first slide's id. Catches navigation clamping bugs and empty-state regressions.

```swift
for _ in 0..<200 {
    live.next()
    XCTAssertNotEqual(live.content, .empty,
                      "navigator should never bottom out into the empty state")
}
```

**TypeScript equivalent (Jest)**

```ts
for (let i = 0; i < 200; i++) {
  live.next();
  expect(live.content).not.toEqual(LiveContent.empty);
  // "navigator should never bottom out into the empty state"
}
```

**Swift syntax:**
- `for _ in 0..<200` — loop 200 times; `0..<200` is a *half-open range* (0 through 199, 200 excluded), and `_` discards the loop variable since it's unused. JS: `for (let i = 0; i < 200; i++)`.
- `live.content != .empty` — `.empty` is enum-case shorthand for `LiveContent.empty`; `!=` compares the enum value. (`LiveContent` is `Equatable`.)
- `XCTAssertNotEqual(a, b, "msg")` — the trailing string is the failure message.

### `testProgramSlidesAreSnapshotsAndSurviveContainerDrop` `@MainActor throws`
Creates a song inside a `do { }` block, snapshots it into `[LiveState.ProgramSlide]`, and lets the `ModelContainer` + `ModelContext` deallocate at the brace. Outside the block — with the database gone — it arms the snapshots, steps once, and pattern-matches `.slide(let renderable)` to confirm the content still has elements. This is the edit/live-separation invariant in action: live output works on immutable value snapshots, so the model going away can't blank the audience screen.

```swift
let snapshots: [LiveState.ProgramSlide]
do {
    // ... build a song in a fresh container/context ...
    snapshots = LiveState.programSlides(for: song)
}   // context + container deallocate here
// ...
if case .slide(let renderable) = live.content {
    XCTAssertFalse(renderable.elements.isEmpty)
} else {
    XCTFail("expected a slide snapshot, got \(live.content)")
}
```

**TypeScript equivalent (Jest)**

```ts
let snapshots: ProgramSlide[];
{
  // ... build a song in a fresh container/context ...
  snapshots = LiveState.programSlides(song);
}   // analogy: the DB connection goes out of scope here (GC'd)
// ...
// `if case .slide(let renderable)` ≈ a tagged-union check that binds the payload.
if (live.content.kind === "slide") {
  const renderable = live.content.value;
  expect(renderable.elements.length === 0).toBe(false);
} else {
  fail(`expected a slide snapshot, got ${live.content}`);
}
```

**Swift syntax:**
- `let snapshots: [LiveState.ProgramSlide]` — a declaration with an *explicit type* but no value yet; it's assigned exactly once inside the `do` block (Swift allows deferred assignment of a `let` if it's provably set before use). `[…]` is array-of; `ProgramSlide` is nested inside `LiveState`.
- `do { }` — here a plain *scoping block* (not error handling): the `container`/`context` declared inside deallocate at the closing brace. That's the whole point — the test proves the snapshots survive the DB going away.
- `if case .slide(let renderable) = live.content { }` — *pattern matching* on an enum with an associated value. `LiveContent` is a tagged union; the `.slide` case carries a `RenderableSlide` payload, and `let renderable` binds it. The closest TS shape is a discriminated union checked by `kind` with the payload pulled out.
- `\(live.content)` — string interpolation (`${…}`) inside the failure message.

### `testSlidePrewarmerEvictsBeyondLimit` `@MainActor`
Clears the shared `SlidePrewarmer`, then prewarms 12 distinct (slide × size) combinations against a default cache limit of 6. Asserts `cachedCount <= 6` — the LRU evicts so memory can't grow unbounded during a long service. Catches a prewarmer cache leak.

```swift
for n in 0..<12 {
    let slide = RenderableSlide(
        backgroundColorHex: String(format: "#%06X", n * 0x111111 % 0xFFFFFF),
        elements: [])
    _ = prewarmer.prewarm(slide, pixelSize: CGSize(width: 200, height: 112))
}
XCTAssertLessThanOrEqual(prewarmer.cachedCount, 6)
```

**TypeScript equivalent (Jest)**

```ts
for (let n = 0; n < 12; n++) {
  const slide = new RenderableSlide({
    backgroundColorHex: "#" + ((n * 0x111111) % 0xFFFFFF).toString(16).padStart(6, "0").toUpperCase(),
    elements: [],
  });
  prewarmer.prewarm(slide, { width: 200, height: 112});   // result discarded
}
expect(prewarmer.cachedCount).toBeLessThanOrEqual(6);
```

**Swift syntax:**
- `for n in 0..<12` — half-open range loop (`n = 0…11`).
- `String(format: "#%06X", …)` — C-style printf formatting; `%06X` is zero-padded 6-digit uppercase hex. JS: `.toString(16).padStart(6, "0").toUpperCase()`.
- `_ = prewarmer.prewarm(...)` — `_ =` explicitly *discards* a return value. Swift warns about unused results from non-void functions; `_ =` silences it. In JS you'd just call it and ignore the value.

### `testSlidePrewarmerHitReturnsCachedImage` `@MainActor`
Prewarms one slide, then asks for it again; the returned image must be the **same instance** (`first === cached`), proving a cache *hit* reuses the rendered image instead of re-rendering. Catches the cache silently missing on a repeated lookup.

```swift
let first = prewarmer.prewarm(slide, pixelSize: size)
let cached = prewarmer.image(for: slide, pixelSize: size)
XCTAssertNotNil(first)
XCTAssertTrue(first === cached)
```

**TypeScript equivalent (Jest)**

```ts
const first = prewarmer.prewarm(slide, size);
const cached = prewarmer.image(slide, size);
expect(first).not.toBeNull();
expect(first).toBe(cached);   // === reference identity, same object
```

**Swift syntax:**
- `first === cached` — `===` is *reference identity* (same object instance), distinct from `==` (value equality). `CGImage` is a reference type, so this asserts the cache handed back the very same image, not an equal copy. JS `===` on objects behaves the same way (`toBe` in Jest).

## How it connects

Exercises `LiveState` (`programSlides`, `arm`, `next`, `previous`, `content`, `liveSlideID`, `ProgramSlide`), the content pipeline (`ContentRebuilder.setLyrics`), the SwiftData models `Playlist` / `PlaylistEntry` / `Item`, the missing-media fallback path (videos with non-existent `mediaFilename`), and the `SlidePrewarmer` LRU cache + renderer routing.

## What it does NOT cover

This is headless soak only. The *real* reliability gate — driving an actual external display for a full service, AVFoundation playback smoothness, display unplug/replug recovery — is a hardware dress rehearsal documented in `docs/DRESS-REHEARSAL.md`. Passing this file proves the logic stays stable under load; it does not prove the hardware does.

## Glossary (Swift → TS/Jest/Node)

- **`final class FooTests: XCTestCase`** → `describe("Foo", ...)`.
- **`func testX() throws`** → `it("x", ...)`; `throws` means a thrown error fails the test.
- **`@MainActor`** → run on the main thread (SwiftData, `LiveState`, prewarmer); no JS equivalent.
- **`XCTAssertNotNil(x)`** → `expect(x).not.toBeNull()`.
- **`XCTFail("msg")`** → `fail("msg")` / forced failure in an unexpected branch.
- **Half-open range `0..<200`** → `for (let i = 0; i < 200; i++)`.
- **`_` (wildcard / `_ =`)** → discard an unused loop var or return value.
- **`.empty` / `.slide` (enum shorthand)** → `EnumName.case` with the type inferred.
- **`if case .slide(let x) = value`** → pattern-match a discriminated union and bind its payload (`value.kind === "slide"` → `value.value`).
- **`===` vs `==`** → reference identity vs value equality; `toBe` vs `toEqual`.
- **`String(format: "#%06X", n)`** → printf-style hex formatting (`.toString(16).padStart(6,"0")`).
- **String interpolation `\(x)`** → `${x}`.
- **`do { }` (plain block)** → a scoping `{ }` block; here it drops the DB connection to prove snapshots survive.
