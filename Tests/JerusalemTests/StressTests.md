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

### `testProgramSlidesAreSnapshotsAndSurviveContainerDrop` `@MainActor throws`
Creates a song inside a `do { }` block, snapshots it into `[LiveState.ProgramSlide]`, and lets the `ModelContainer` + `ModelContext` deallocate at the brace. Outside the block — with the database gone — it arms the snapshots, steps once, and pattern-matches `.slide(let renderable)` to confirm the content still has elements. This is the edit/live-separation invariant in action: live output works on immutable value snapshots, so the model going away can't blank the audience screen.

```swift
snapshots = LiveState.programSlides(for: song)
}   // context + container deallocate here
...
if case .slide(let renderable) = live.content {
    XCTAssertFalse(renderable.elements.isEmpty)
}
```

### `testSlidePrewarmerEvictsBeyondLimit` `@MainActor`
Clears the shared `SlidePrewarmer`, then prewarms 12 distinct (slide × size) combinations against a default cache limit of 6. Asserts `cachedCount <= 6` — the LRU evicts so memory can't grow unbounded during a long service. Catches a prewarmer cache leak.

### `testSlidePrewarmerHitReturnsCachedImage` `@MainActor`
Prewarms one slide, then asks for it again; the returned image must be the **same instance** (`first === cached`), proving a cache *hit* reuses the rendered image instead of re-rendering. Catches the cache silently missing on a repeated lookup.

## How it connects

Exercises `LiveState` (`programSlides`, `arm`, `next`, `previous`, `content`, `liveSlideID`, `ProgramSlide`), the content pipeline (`ContentRebuilder.setLyrics`), the SwiftData models `Playlist` / `PlaylistEntry` / `Item`, the missing-media fallback path (videos with non-existent `mediaFilename`), and the `SlidePrewarmer` LRU cache + renderer routing.

## What it does NOT cover

This is headless soak only. The *real* reliability gate — driving an actual external display for a full service, AVFoundation playback smoothness, display unplug/replug recovery — is a hardware dress rehearsal documented in `docs/DRESS-REHEARSAL.md`. Passing this file proves the logic stays stable under load; it does not prove the hardware does.
