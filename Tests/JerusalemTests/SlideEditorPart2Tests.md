# `SlideEditorPart2Tests.swift`

> Headless gate tests for the Phase 8 "Part 2" editor features: aspect ratio, inspector tabs, canvas zoom math, deep text styling, gradient/color backgrounds, theme copy/apply, and persistence of all the new model fields.

**Location:** `Tests/JerusalemTests/SlideEditorPart2Tests.swift`
**Role:** XCTest unit tests

## What it does (plain English)

Where `SlideEditorTests.swift` covered the "Part 1" geometry core, this file is the checklist for the *second* batch of editor features. Each test maps to a checkpoint in `docs/PHASE-8-PART-2-PLAN.md` and deliberately picks the slice that a headless test can observe — the rest (the actual UX of dragging, pinching, clicking) is hand-verified per `docs/DRESS-REHEARSAL.md`.

It checks three kinds of thing. First, **pure logic**: aspect-ratio parsing, which inspector tab to show, and the clamp/apply math for canvas zoom. Second, **value-snapshot round-trips**: when you set a fancy typography field on a `SlideElement` model, does it copy correctly into the immutable `RenderableElement` the renderer actually uses? Third, **pixel proofs**: render a slide to an image and inspect actual pixels to prove underline, gradients, and solid fills really happen.

The final test is a persistence smoke test — write the new fields to a real on-disk SwiftData store, close it, reopen it, and confirm everything survived. This matters because SwiftData has to know about every new field for crash-recovery to work.

## XCTest you'll meet in this file

| XCTest API | Jest equivalent |
| --- | --- |
| `func testFoo() throws` | `it('foo', ...)` that fails if it throws |
| `XCTAssertEqual(a, b, accuracy: 1e-9)` | `expect(a).toBeCloseTo(b)` |
| `XCTAssertEqual([...], [...])` | `expect(arr).toEqual([...])` — deep array equality |
| `XCTAssertTrue/False(x)` | `expect(x).toBe(true/false)` |
| `XCTAssertGreaterThan(a, b)` | `expect(a).toBeGreaterThan(b)` |
| `try XCTUnwrap(optional)` | assert-non-null-and-return the value (fails the test if `nil`) |
| `XCTAssertFalse(cond, "msg")` | `expect(cond).toBe(false)` with a failure message |
| `addTeardownBlock { ... }` | an `afterEach` registered inline mid-test (cleanup that runs after) |
| `@MainActor` | the test runs on the main thread (required for SwiftData here) |

## The tests, one by one

### `testAspectRatioDefaultsTo16x9AndParsesOverrides`
`Item.aspectRatioValue` defaults to `16:9`, parses `"4:3"` into `4.0/3.0`, and falls back to `16:9` for `"garbage"`. Catches a bad aspect-ratio string crashing or silently producing a wrong number.

### `testInspectorTabAutoSwitchAndCases`
`InspectorTab.onSelectionChange(hasSelection:)` returns `.format` when an object is selected and `.slide` when nothing is. Also pins the tab order (`[.format, .arrange, .slide]`) and their titles. Catches the inspector showing the wrong panel after a selection change.

```swift
XCTAssertEqual(InspectorTab.onSelectionChange(hasSelection: true), .format)
XCTAssertEqual(InspectorTab.allCases.map(\.title), ["Format", "Arrange", "Slide"])
```

### `testCanvasZoomClampsAndApplies`
`CanvasZoomMath` clamps zoom to `0.5...2.0`, applies a pinch magnification (`applying(magnify:to:)`), and applies a ⌘-scroll delta (`applying(scroll:to:)`), always clamped. Catches runaway zoom from an aggressive pinch or scroll.

```swift
XCTAssertEqual(CanvasZoomMath.applying(magnify: 5, to: 1.0), 2.0, accuracy: 1e-9)  // clamps
```

### `testJustifyAlignmentRoundTripsThroughSnapshot`
A `SlideElement` with `.justified` alignment copies that value into its `RenderableElement` snapshot. Catches a new alignment case being dropped on the way to the renderer.

### `testTypographyDepthFieldsCopyIntoRenderable`
Sets eight deep-styling fields on a model (line spacing, letter spacing, stroke width/color, shadow blur/offset/color, underline) and asserts every one copies into the `RenderableElement`. The renderer only ever sees the snapshot, so a missed field would silently never render.

### `testUnderlinedTextRasterizesExtraPixels` `throws`
A genuine pixel proof: render `"HELLO"` with and without underline, then count non-black pixels. The underlined image must have *more* (the underline fills extra rows). Uses the private `nonBlackPixelCount` helper that draws the `CGImage` into a raw RGBA buffer and counts pixels above a brightness threshold.

```swift
XCTAssertGreaterThan(nonBlackPixelCount(a), nonBlackPixelCount(b))
```

### `testGradientBackgroundDiffersAtTopVsBottom` `throws`
Renders a `.gradient` background (red→blue, angle 90°) and reads two pixels — top vs bottom. They must differ in color, which is the whole point of a gradient. Catches a gradient that collapsed to a flat fill.

### `testColorBackgroundKindFillsTheWholeSlide` `throws`
The contrast case: a `.color` background must be *uniform* — top and bottom pixels both read pure red `(255, 0, 0)`. Catches a solid background accidentally bleeding a gradient.

### `testThemeCopyCapturesElementTypography`
`Theme.copy(from: element)` (the "Set as default" action) must absorb every typography field from an element into the theme. Seventeen assertions confirm font, color, alignment, bold/italic/underline, shadow/stroke toggles, autofit, and all the depth fields. Catches "Set as default" forgetting a field.

### `testThemeAppliedAfterCopyProducesMatchingElement`
The round-trip's other half: after `theme.copy(from:)`, calling `theme.apply(to: freshElement)` must reproduce the same typography on a brand-new element. Proves copy and apply are symmetric.

### `testNewSlideElementAndSlideFieldsPersistAcrossContexts` `@MainActor throws`
The persistence smoke test. It builds a real on-disk store (not in-memory), writes an `Item` with a `4:3` aspect ratio, a `Slide` with a gradient background, and a `SlideElement` with depth styling, then `save()`s. It opens a **fresh** `ModelContainer` + `ModelContext` against the same file and re-fetches, asserting every field survived. The `addTeardownBlock` cleans up the `.store`, `-wal`, and `-shm` files afterward.

```swift
addTeardownBlock {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
    }
}
```

## How it connects

Exercises `Item.aspectRatioValue`, `InspectorTab`, `CanvasZoomMath`, `SlideElement`, `RenderableElement`, `RenderableSlide`, `Theme.copy/apply`, the shared `SlideRenderer.makeImage`, and the SwiftData schema (`Persistence.schema`, `ModelContainer`, `Slide`).

## What it does NOT cover

The interactive UX — actually dragging with snap, pinch-zooming with a trackpad, clicking the segmented inspector bar, picking gradient stops in a color well — is hand-verified on real hardware (`docs/DRESS-REHEARSAL.md` §10.1–§10.6). These tests cover the math, the snapshots, the pixels, and the persistence.
