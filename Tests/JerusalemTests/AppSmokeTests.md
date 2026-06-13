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

**TypeScript equivalent (Jest)**

```ts
// analogy: a TS string enum stands in for Swift's String-backed enum.
enum EditorMode {
  Show = "Show",
  Edit = "Edit",
}

expect(Object.values(EditorMode).length).toEqual(2); // analogy: allCases.count
expect(EditorMode.Show).toEqual("Show");             // analogy: .show.rawValue
expect(EditorMode.Edit).toEqual("Edit");
```

**Swift syntax:**
- `final class AppSmokeTests: XCTestCase { … }` — shape: a class that subclasses `XCTestCase` becomes a test suite; `final` just means "no subclassing." Jest analog: `describe("AppSmokeTests", () => { … })`.
- `func testSlideEditorModeHasShowAndEdit()` — shape: any method whose name starts with `test` is auto-discovered and run as a test case. Jest analog: `it("slideEditorModeHasShowAndEdit", () => { … })` — the method name *is* the `it` title.
- `XCTAssertEqual(a, b)` — shape: the workhorse equality assert. Jest analog: `expect(a).toEqual(b)`.
- `enum … : String, CaseIterable` (the `EditorMode` it inspects) — shape: a `String`-backed enum gets `.rawValue` (the backing string) for free, and `CaseIterable` synthesizes `.allCases` (an array of every case). Jest analog: a TS string enum plus `Object.values(MyEnum)`.

`allCases.count` works because the enum conforms to `CaseIterable` (Swift auto-generates an `allCases` array — like `Object.values(MyEnum)`). The `rawValue` is the underlying `String` each case is backed by (similar to a TypeScript string enum `enum EditorMode { Show = "Show", Edit = "Edit" }`).

**Real bug it would catch:** if `@testable import Jerusalem` broke (renamed module, missing target dependency) or if someone deleted/renamed the `EditorMode` enum, this test would fail to compile — surfacing a broken test setup immediately rather than letting the whole suite silently rot.

> Note: per the project memory, Phase 8.5 later *removed* the operator's Show/Edit mode toggle. This test references an enum that may have shifted in meaning since Phase 0; it remains useful purely as a build/link smoke check.

## How it connects
Exercises `SlideEditorView.EditorMode` from the app module. More importantly, it exercises the *test target's ability to import and reference the app module at all*.

## What it does NOT cover
Everything meaningful. No persistence, no rendering, no live output, no UI behavior. It is intentionally trivial.

## XCTest → Jest glossary
- `final class X: XCTestCase { }` — shape: subclass of `XCTestCase` holding the tests. Jest analog: `describe("X", () => { … })`.
- `func testFoo()` — shape: method whose name starts with `test`, auto-run. Jest analog: `it("foo", () => { … })` (the method name becomes the title).
- `XCTAssertEqual(a, b)` — shape: deep/value equality assertion. Jest analog: `expect(a).toEqual(b)`.
- `@testable import Jerusalem` — shape: imports the app module *with internal access* so tests can see non-public symbols. Jest analog: `import { … } from "../src"` (Jest has no access-level concept; everything exported is reachable).
- `enum … : String` / `.rawValue` / `CaseIterable` / `.allCases` — shape: a string-backed enum exposes each case's backing string via `.rawValue`, and `CaseIterable` gives an `.allCases` array. Jest analog: a TS string enum + `Object.values(MyEnum)`.
