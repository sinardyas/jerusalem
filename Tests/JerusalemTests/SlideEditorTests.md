# `SlideEditorTests.swift`

> Headless unit tests for the pure geometry math behind the slide editor (snap, clamp, drag/resize, alignment guides, layer reorder) plus the content rebuilder's promise to never clobber hand-edited slides.

**Location:** `Tests/JerusalemTests/SlideEditorTests.swift`
**Role:** XCTest unit tests

## What it does (plain English)

The slide editor lets a user drag and resize text/image boxes on a canvas. All of the *decidable* math — where a box lands when you drop it, how big it can get, when it should snap to a guide line, and how layers reorder — lives in a caseless `enum SlideGeometry` namespace of pure functions. Pure functions are easy to test without any UI, so this file pokes at each rule directly and checks the numbers.

Think of `SlideGeometry` as a stateless utility module (like a `geometry.ts` file exporting plain functions). Every test here is "call the function with known inputs, assert the exact output," which is exactly how you'd unit-test that module in JavaScript with Jest.

The last test crosses into SwiftData territory: it verifies that once a user manually edits a slide (`isManuallyEdited = true`), re-running `ContentRebuilder.rebuild` leaves that slide alone — the reliability promise that auto-regeneration never destroys someone's hand-tuned slide.

## XCTest you'll meet in this file

| XCTest API | Jest equivalent |
| --- | --- |
| `final class SlideEditorTests: XCTestCase` | `describe('SlideEditor', ...)` |
| `func testFoo()` | `it('foo', ...)` |
| `XCTAssertEqual(a, b, accuracy: 1e-9)` | `expect(a).toBeCloseTo(b)` — float-tolerant equality |
| `XCTAssertGreaterThanOrEqual(a, b)` | `expect(a).toBeGreaterThanOrEqual(b)` |
| `XCTAssertLessThanOrEqual(a, b)` | `expect(a).toBeLessThanOrEqual(b)` |
| `XCTAssertNotNil(x)` / `XCTAssertNil(x)` | `expect(x).not.toBeNull()` / `expect(x).toBeNull()` |
| `@MainActor func test...() throws` | a test that must run on the main thread (needed for SwiftData) and fails if it throws |

`accuracy: 1e-9` shows up everywhere because these are floating-point coordinates in the `0...1` range; exact `==` on floats is unreliable, so the tests allow a tiny tolerance.

## The tests, one by one

### `testClampedAllowsOverflowWithinPasteboardAndKeepsMinimumSize`
Exercises `SlideGeometry.clamped`. A box can now hang partly off the slide (the "pasteboard" — a margin around the 0...1 slide area), so a frame at `x: -0.3, y: 1.1` is preserved as-is. But a *far*-off frame gets pinned to the pasteboard edge, never beyond. It also checks a minimum width (`>= 0.05`) and a height cap (`<= 1.0 + 2 * margin`). Catches a box being lost off-screen or shrunk to nothing.

```swift
let far = SlideGeometry.clamped(.init(x: 5, y: -5, width: 0.3, height: 0.3))
XCTAssertEqual(far.x, 1.0 + margin - 0.3, accuracy: 1e-9)   // pinned at the right pasteboard edge
```

**TypeScript equivalent (Jest)**

```ts
const far = SlideGeometry.clamped({ x: 5, y: -5, width: 0.3, height: 0.3 });
expect(far.x).toBeCloseTo(1.0 + margin - 0.3);   // pinned at the right pasteboard edge
```

**Swift syntax:**
- `enum SlideGeometry` — a *caseless enum* used purely as a namespace of `static` functions. It has no instances; it's the Swift idiom for "a module of pure functions," like a `geometry.ts` exporting plain functions. (`SlideGeometry.clamped(...)` ≈ `import * as SlideGeometry`.)
- `.init(x: 5, ...)` — leading-dot shorthand for the `Frame` struct's initializer; the type is inferred from the parameter, so you skip the name. In TS just an object literal `{ x: 5, ... }`.
- `accuracy: 1e-9` — float-tolerant compare (Jest's `toBeCloseTo`), since these are `0...1` floating-point coordinates.

### `testSnappedRoundsToNearestGridStep`
`SlideGeometry.snapped(_:step:enabled:)` rounds a single coordinate to the nearest grid step (e.g. `0.12 → 0.10`, `0.13 → 0.15` at step `0.05`). When `enabled: false`, the value passes through untouched. Catches snap-to-grid rounding the wrong way or ignoring the toggle.

```swift
XCTAssertEqual(SlideGeometry.snapped(0.12, step: 0.05, enabled: true), 0.10, accuracy: 1e-9)
XCTAssertEqual(SlideGeometry.snapped(0.12, step: 0.05, enabled: false), 0.12, accuracy: 1e-9)
```

**TypeScript equivalent (Jest)**

```ts
expect(SlideGeometry.snapped(0.12, { step: 0.05, enabled: true })).toBeCloseTo(0.10);
expect(SlideGeometry.snapped(0.12, { step: 0.05, enabled: false })).toBeCloseTo(0.12);
```

**Swift syntax:**
- `snapped(_:step:enabled:)` — the function's full name with its argument labels. The first `_` means the first argument has *no* label (call it positionally: `snapped(0.12, ...)`); `step:` and `enabled:` are labeled. TS has no labels, so we pass an options object.

### `testSnappedFrameMaintainsMinimumDimensions`
`snappedToGrid` snaps a whole frame and still enforces the `0.05` minimum height even after a tiny box snaps. Catches snapping producing a zero-height box.

### `testBodyDragMovesWithoutChangingSize`
`SlideGeometry.dragged(_:by:dy:handle:)` with `handle: .body` moves the box (`x += 0.05`, `y -= 0.02`) but leaves width/height unchanged. This is dragging the body of a box, not a resize handle.

```swift
let start = SlideGeometry.Frame(x: 0.10, y: 0.20, width: 0.30, height: 0.40)
let dragged = SlideGeometry.dragged(start, by: 0.05, dy: -0.02, handle: .body)
XCTAssertEqual(dragged.x, 0.15, accuracy: 1e-9)
```

**TypeScript equivalent (Jest)**

```ts
const start = new SlideGeometry.Frame({ x: 0.10, y: 0.20, width: 0.30, height: 0.40 });
const dragged = SlideGeometry.dragged(start, { by: 0.05, dy: -0.02, handle: Handle.body });
expect(dragged.x).toBeCloseTo(0.15);
```

**Swift syntax:**
- `SlideGeometry.Frame(...)` — a nested `struct` (a value type) declared inside the `SlideGeometry` namespace; `struct`s are copied on assignment (no shared references), which is why "drag" returns a fresh frame instead of mutating `start`.
- `handle: .body` — leading-dot enum case again (`Handle.body`).

### `testTopLeftHandleResizesUpAndLeft` / `testBottomRightHandleResizesDownAndRight`
Same `dragged` function but with corner handles. The top-left handle moves the origin and grows the box up/left; the bottom-right handle keeps the origin fixed and grows down/right. Catches resize math anchoring the wrong corner.

```swift
let dragged = SlideGeometry.dragged(start, by: -0.05, dy: -0.10, handle: .topLeft)
XCTAssertEqual(dragged.width, 0.45, accuracy: 1e-9)   // grew by 0.05
XCTAssertEqual(dragged.height, 0.40, accuracy: 1e-9)  // grew by 0.10
```

**TypeScript equivalent (Jest)**

```ts
const dragged = SlideGeometry.dragged(start, { by: -0.05, dy: -0.10, handle: Handle.topLeft });
expect(dragged.width).toBeCloseTo(0.45);   // grew by 0.05
expect(dragged.height).toBeCloseTo(0.40);  // grew by 0.10
```

### `testAlignmentCandidatesIncludeSlideAndOtherElements`
`SlideGeometry.alignmentCandidates(against:)` returns the snap lines a dragged box can align to: the slide's own edges/center (`0`, `0.5`, `1`) plus the edges and center of *other* elements. Because those candidates come from FP arithmetic (`x + width`), the test uses a private `approximatelyContains` helper instead of exact `contains`.

```swift
private func approximatelyContains(_ values: [Double], _ target: Double,
                                   tolerance: Double = 1e-9) -> Bool {
    values.contains { abs($0 - target) < tolerance }
}
```

**TypeScript equivalent (Jest)**

```ts
function approximatelyContains(values: number[], target: number, tolerance = 1e-9): boolean {
  return values.some($0 => Math.abs($0 - target) < tolerance);
}
```

**Swift syntax:**
- `private func` — file/type-private visibility; the helper isn't part of the public test surface. TS: a non-exported module function.
- `[Double]` — array of `Double` (`Double[]` → `number[]`).
- `tolerance: Double = 1e-9` — a default parameter value, same idea as TS's `tolerance = 1e-9`.
- `-> Bool` — the return type annotation (`: boolean`).
- `values.contains { abs($0 - target) < tolerance }` — `contains` takes a *trailing closure* predicate; `$0` is the implicit first parameter (the current element). Equivalent to `values.some($0 => ...)`. (`abs` is Swift's `Math.abs`.)

### `testSnapVerticalCatchesNearbyCenter`
`SlideGeometry.snapVertical(frame:candidates:)` returns a snap result when a box's center is near a candidate line. A box centered at `0.50` snaps to the slide center, returning `line == 0.5` and `anchor == .center`. Catches the snap threshold being too tight/loose or reporting the wrong anchor.

```swift
let snap = SlideGeometry.snapVertical(frame: near, candidates: candidates)
XCTAssertNotNil(snap)
XCTAssertEqual(snap?.line, 0.5)
XCTAssertEqual(snap?.anchor, .center)
```

**TypeScript equivalent (Jest)**

```ts
const snap = SlideGeometry.snapVertical({ frame: near, candidates });
expect(snap).not.toBeNull();
expect(snap?.line).toEqual(0.5);
expect(snap?.anchor).toEqual(Anchor.center);
```

**Swift syntax:**
- `snap?.line` — optional chaining: `snapVertical` returns an optional result (`Snap?`), so `?.` reads `.line` only if it's non-`nil`, else yields `nil`. Identical to TS `snap?.line`.

### `testSnapVerticalIgnoresFarAnchors`
The mirror case: a box whose center is *not* near any candidate returns `nil` (no snap). Catches false-positive snapping.

```swift
XCTAssertNil(SlideGeometry.snapVertical(frame: far, candidates: candidates))
```

**TypeScript equivalent (Jest)**

```ts
expect(SlideGeometry.snapVertical({ frame: far, candidates })).toBeNull();
```

### `testRaiseSwapsWithNeighborAndClampsAtTop`
`SlideGeometry.raised(_:in:)` swaps an element one step toward the front. `raised(2, in: [1,2,3]) → [1,3,2]`. Raising the already-top element or a missing element is a no-op. Catches layer-order off-by-one and out-of-bounds.

```swift
XCTAssertEqual(SlideGeometry.raised(2, in: [1, 2, 3]), [1, 3, 2])
XCTAssertEqual(SlideGeometry.raised(9, in: [1, 2, 3]), [1, 2, 3])   // not present
```

**TypeScript equivalent (Jest)**

```ts
expect(SlideGeometry.raised(2, [1, 2, 3])).toEqual([1, 3, 2]);
expect(SlideGeometry.raised(9, [1, 2, 3])).toEqual([1, 2, 3]);   // not present
```

**Swift syntax:**
- `raised(2, in: [1, 2, 3])` — `2` is positional (the element to raise), `in:` is the labeled array argument. `[1, 2, 3]` is an array literal (same as JS).
- `XCTAssertEqual([...], [...])` — compares arrays element-by-element (deep equality), like Jest's `toEqual`.

### `testLowerMirrorsRaise`
`SlideGeometry.lowered` is the symmetric move toward the back; lowering the bottom element is a no-op.

### `testMoveToFrontAndBackSendsItemToEnds`
`movedToFront` / `movedToBack` jump an element all the way to either end. Includes no-op cases for absent elements and elements already at the target end.

### `testRebuilderYieldsToManuallyEditedSlides` `@MainActor`
The cross-system test. It spins up a throwaway in-memory SwiftData store, creates a song, sets lyrics (which generates 2 slides via `ContentRebuilder.setLyrics`), then simulates a hand-edit by setting a slide's text to `"EDITED"` and flagging `isManuallyEdited = true`. Re-running `ContentRebuilder.rebuild` must **not** overwrite that text. It then confirms an *un-edited* song still rebuilds normally when `linesPerSlide` changes (1 slide becomes 2). This is the heart of the reliability promise.

```swift
let container = try ModelContainer(
    for: Persistence.schema,
    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
let context = ModelContext(container)
// ...
song.orderedSlides.first?.isManuallyEdited = true
ContentRebuilder.rebuild(song)
XCTAssertEqual(song.orderedSlides.first?.orderedElements.first?.text, editedText)
```

**TypeScript equivalent (Jest)**

```ts
// analogy: in-memory ModelContainer ≈ a throwaway SQLite/Prisma DB created per-test.
const container = await openInMemoryDb(Persistence.schema);
const context = container.newContext();
// ...
const slide = song.orderedSlides[0];
if (slide) slide.isManuallyEdited = true;          // first? → guard against empty
ContentRebuilder.rebuild(song);
expect(song.orderedSlides[0]?.orderedElements[0]?.text).toEqual(editedText);
```

**Swift syntax:**
- `ModelConfiguration(isStoredInMemoryOnly: true)` — a SwiftData store that lives only in RAM and vanishes when the test ends — the standard "throwaway test DB" pattern (`// analogy:` an in-memory SQLite).
- `ModelContainer(for:configurations:)` / `ModelContext(container)` — the store, then a session to read/write through it.
- `.first?.…?.…` — `first` returns an *optional* (the array might be empty), so the chained `?.` accesses keep yielding `nil` instead of crashing if any link is missing. Same as TS `arr[0]?.x?.y`.

## How it connects

Exercises the production `SlideGeometry` namespace (`SlideGeometry.swift`) — clamp, snap, drag/resize, alignment guides, layer reorder — and `ContentRebuilder` plus the SwiftData models `Item`, `Slide`, `SlideElement`, `Theme`.

## What it does NOT cover

The actual drag-and-drop UX, live canvas rendering, and the Phase 8 UX goal ("a non-designer makes a good-looking slide in under a minute") are hardware/interaction gates verified by hand, not here. This suite only covers the math and the rebuild-skip rule.

## Glossary (Swift → TS/Jest/Node)

- **`final class FooTests: XCTestCase`** → `describe("Foo", ...)`; `final` = not subclassable.
- **`func testX()` / `func testX() throws`** → `it("x", ...)`; `throws` means a thrown error fails the test.
- **`@MainActor`** → run on the main thread (needed for SwiftData); no JS equivalent.
- **`enum X` (caseless)** → a namespace/module of `static` functions, like `import * as X`.
- **`struct X`** → a *value type*: copied on assignment, so functions return fresh values instead of mutating shared objects.
- **Argument labels (`raised(_:in:)`, `step:`, `enabled:`)** → no TS equivalent; modeled as positional args or an options object.
- **`.init(...)` / `.body` / `.center`** → leading-dot shorthand for an initializer or enum case with the type inferred from context.
- **Optionals (`T?`, `?.`, `XCTAssertNil/NotNil`)** → `T | null`, optional chaining, `toBeNull()`/not.
- **Closures / trailing closure / `$0`** → arrow functions; `{ ... }` after a call is the last arg; `$0` is the first implicit parameter.
- **`[Double]` / array literal `[1,2,3]`** → `number[]` / `[1,2,3]`.
- **Default parameter (`tolerance: Double = 1e-9`)** → `tolerance = 1e-9`.
- **`accuracy:`** → `toBeCloseTo` — float-tolerant equality.
- **`ModelContainer` / `ModelConfiguration` / `ModelContext`** → DB connection / config / session (`// analogy:` an ORM); `isStoredInMemoryOnly: true` → throwaway in-memory DB.
- **`abs`** → `Math.abs`.
