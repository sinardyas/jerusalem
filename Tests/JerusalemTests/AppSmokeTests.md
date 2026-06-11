# `AppSmokeTests.swift`

> A bare-minimum "does the test target even build and link against the app?" check — the Phase 0 heartbeat before real coverage exists.

**Location:** `Tests/JerusalemTests/AppSmokeTests.swift`
**Role:** XCTest unit tests (Phase 0 smoke check)

## What it does (plain English)
This is the very first test that ever existed in the project. Its only job is to prove three boring-but-essential things: the test bundle compiles, it links against the `Jerusalem` app module (via `@testable import Jerusalem`), and it can actually reference real types from that module. If this file fails to even build, nothing else in the suite can run, so it acts as a canary.

The single test pokes at one app enum (`SlideEditorView.EditorMode`) just to have *something* concrete to assert against. Think of it as the equivalent of a Jest `it('renders without crashing')` — it isn't testing meaningful behavior, it's testing that the wiring between the test target and the app target is intact.

Because it's so minimal, real reliability coverage lives in the Phase 1+ files (`PersistenceTests`, `SlideRenderingTests`, etc.). This file just keeps the lights on.

## XCTest you'll meet in this file
- `final class AppSmokeTests: XCTestCase` — the test suite, like a Jest `describe('AppSmokeTests', ...)`.
- `func testSlideEditorModeHasShowAndEdit()` — one test case (name must start with `test`), like an `it(...)`.
- `XCTAssertEqual(a, b)` — `expect(a).toEqual(b)`.

## The tests, one by one

### `testSlideEditorModeHasShowAndEdit`
Sets up nothing — there's no `setUp`. It directly inspects the `SlideEditorView.EditorMode` enum and asserts it has exactly two cases (`show` and `edit`) and that their `rawValue` strings are `"Show"` and `"Edit"`.

```swift
XCTAssertEqual(SlideEditorView.EditorMode.allCases.count, 2)
XCTAssertEqual(SlideEditorView.EditorMode.show.rawValue, "Show")
XCTAssertEqual(SlideEditorView.EditorMode.edit.rawValue, "Edit")
```

`allCases.count` works because the enum conforms to `CaseIterable` (Swift auto-generates an `allCases` array — like `Object.values(MyEnum)`). The `rawValue` is the underlying `String` each case is backed by (similar to a TypeScript string enum `enum EditorMode { Show = "Show", Edit = "Edit" }`).

**Real bug it would catch:** if `@testable import Jerusalem` broke (renamed module, missing target dependency) or if someone deleted/renamed the `EditorMode` enum, this test would fail to compile — surfacing a broken test setup immediately rather than letting the whole suite silently rot.

> Note: per the project memory, Phase 8.5 later *removed* the operator's Show/Edit mode toggle. This test references an enum that may have shifted in meaning since Phase 0; it remains useful purely as a build/link smoke check.

## How it connects
Exercises `SlideEditorView.EditorMode` from the app module. More importantly, it exercises the *test target's ability to import and reference the app module at all*.

## What it does NOT cover
Everything meaningful. No persistence, no rendering, no live output, no UI behavior. It is intentionally trivial.
