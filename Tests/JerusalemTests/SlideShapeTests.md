# `SlideShapeTests.swift`

> Phase 8.4 gate: proves the new `shape` element kind round-trips through the value snapshot, rasterizes through the single shared `SlideRenderer` (rectangle, ellipse, rounded-rect, plus stroke borders), and persists across SwiftData contexts.

**Location:** `Tests/JerusalemTests/SlideShapeTests.swift`
**Role:** XCTest unit tests

## What it does (plain English)

Shapes (rectangle, ellipse, rounded rectangle) are a new kind of slide element alongside text and image. This file verifies them at three levels.

**Round-trip:** setting a shape's type, fill color, and corner radius on the SwiftData `SlideElement` model copies correctly into the immutable `RenderableElement` the renderer reads. It also checks the enum safety net — unknown raw strings decode to `nil`, and a fresh shape defaults to `.rectangle`.

**Rendering:** the shapes actually draw, through the one shared renderer path. A white rectangle on black leaves a big block of bright pixels; a full-bleed ellipse fills its center but leaves its bounding-box *corners* black (because an ellipse doesn't reach the corners); and a stroked rounded-rect adds border pixels without crashing.

**Persistence:** the shape fields survive a real on-disk SwiftData save/reopen cycle, so a shape you draw is still there after a crash and relaunch.

## XCTest you'll meet in this file

| XCTest API | Jest equivalent |
| --- | --- |
| `func testFoo() throws` | `it('foo', ...)` that fails on throw |
| `XCTAssertEqual(a, b)` / `(a, b, accuracy:)` | `expect(a).toEqual(b)` / `toBeCloseTo` |
| `XCTAssertNil(x)` | `expect(x).toBeNull()` |
| `XCTAssertGreaterThan / LessThan(a, b, "msg")` | numeric comparisons with a label |
| `try XCTUnwrap(optional)` | assert-non-null-and-return |
| `addTeardownBlock { ... }` | inline `afterEach` cleanup |
| `@MainActor` | runs on the main thread (for SwiftData) |

## The tests, one by one

### `testShapeRoundTripsThroughRenderableElement`
A `SlideElement(kind: .shape)` with `.ellipse`, fill `#FF0000`, corner radius `24` copies all four properties (`kind`, `shapeType`, `fillColorHex`, `cornerRadius`) into its `RenderableElement` snapshot. Catches a shape field never reaching the renderer.

### `testUnknownShapeAndKindRawFallBackSafely`
`SlideElementKind(rawValue: "bogus")` and `ShapeType(rawValue: "bogus")` both return `nil` (no crash on bad stored data), and a fresh shape element defaults to `.rectangle`. This is the "follow the `…Raw: String` enum convention" safety check.

```swift
XCTAssertNil(ShapeType(rawValue: "bogus"))
XCTAssertEqual(SlideElement(kind: .shape, order: 0).shapeType, .rectangle)
```

### `testShapeRendersDistinctPixels` `throws`
A white rectangle covering the middle 60% of a black slide must leave `> 1000` non-black pixels. Proves shapes render through the shared path. Uses the `nonBackgroundPixelCount` helper (draw to RGBA buffer, count bright pixels).

### `testEllipseLeavesBoundingBoxCornersBackground` `throws`
A full-bleed white ellipse must be filled white at the center (`center.r > 200`) but black at a near-corner pixel `(2,2)` (`corner.r < 40`), because an ellipse inscribed in a box doesn't touch the corners. This proves it's really an ellipse, not a rectangle. Uses the `pixelRGB` helper to sample exact pixels.

```swift
XCTAssertGreaterThan(center.r, 200, "Ellipse center should be filled white")
XCTAssertLessThan(corner.r, 40, "Ellipse must leave its bounding-box corner black")
```

### `testShapeBorderUsesStrokeFields` `throws`
A small black rounded-rect with a thick white stroke (`hasStroke`, `strokeColorHex`, `strokeWidth`) must still render with `> 50` non-background pixels — the border path doesn't crash and adds visible pixels. This is a smoke-level check that stroked shapes work.

### `testShapeFieldsPersistAcrossContexts` `@MainActor throws`
Writes an `Item` → `Slide` → shape `SlideElement` (`.roundedRectangle`, fill `#12AB34`, corner radius `18`) to a real on-disk store and `save()`s. Reopens a fresh `ModelContainer` + `ModelContext`, re-fetches, and asserts all four shape fields survived. The `addTeardownBlock` deletes the `.store`/`-wal`/`-shm` files.

## How it connects

Exercises the `SlideElement` shape fields (`shapeType`, `fillColorHex`, `cornerRadius`), the `SlideElementKind` / `ShapeType` enums, the `RenderableElement` snapshot, the shared `SlideRenderer.makeImage`, and the SwiftData schema (`Persistence.schema`, `Slide`, `Item`).

## What it does NOT cover

Adding a shape from the toolbar, dragging/resizing it on the canvas, and the shape inspector controls are interactive and verified by running the app (noted in the file's own header).
