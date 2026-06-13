# `SlideLayersTests.swift`

> Headless tests for the Layers panel: the pure reorder math that drag-and-drop produces, the renderer drawing elements strictly in `order` (z-order), and the human-readable layer label for each element kind.

**Location:** `Tests/JerusalemTests/SlideLayersTests.swift`
**Role:** XCTest unit tests

## What it does (plain English)

A slide is a stack of elements. The Layers panel shows them front-to-back, and you can drag a row up or down to restack. This file tests three pieces of that feature.

First, `SlideLayers.reorder` — the function that turns a drag ("move row from index 2 to index 0") into new `order` values on the actual `SlideElement` models. The panel shows layers **front-first** (highest `order` at the top), so the test inputs are in front-first order and the assertions check the resulting `order` integers.

Second, the renderer's z-ordering: the shared `SlideRenderer` draws elements in a single pass, back-to-front, so whatever has the highest `order` is drawn last and wins overlapping pixels. The test renders two full-slide shapes and reads the center pixel to prove the top one shows.

Third, `SlideElement.layerName` — the label shown in the panel for each kind (text uses trimmed content, falling back to "Text"; images use the filename; shapes use a type name).

## XCTest you'll meet in this file

| XCTest API | Jest equivalent |
| --- | --- |
| `func testFoo()` / `func testFoo() throws` | `it('foo', ...)` |
| `XCTAssertEqual(a, b, "message")` | `expect(a).toEqual(b)` with a label |
| `XCTAssertGreaterThan / LessThan(a, b, "msg")` | `expect(a).toBeGreaterThan/toBeLessThan(b)` |
| `try XCTUnwrap(optional)` | assert-non-null-and-return |
| `IndexSet(integer: 2)` | how SwiftUI's list-move hands you the dragged row index (a set of indices) |

## The tests, one by one

### `testReorderMovesBackElementToFront`
Three elements `a`(order 0, back), `b`(1), `c`(2, front). Front-first display is `[c, b, a]`. Dragging `a` (display index 2) to display index 0 must make `a` the front-most: `a.order == 2`, `c.order == 1`, `b.order == 0`. Catches reorder writing the wrong order integers or inverting the front/back convention.

```swift
SlideLayers.reorder(frontFirst: [c, b, a], from: IndexSet(integer: 2), to: 0)
XCTAssertEqual(a.order, 2, "moved-to-front element gets the highest order")
```

**TypeScript equivalent (Jest)**

```ts
// analogy: IndexSet(integer: 2) ≈ the source index from a list-move event.
SlideLayers.reorder([c, b, a], new Set([2]), 0);   // (frontFirst, from, to)
expect(a.order).toEqual(2);   // "moved-to-front element gets the highest order"
```

**Swift syntax:**
- `SlideElement(kind: .text, order: 0)` — initializer call with labeled args (no `new`); `.text` is enum-case shorthand for `SlideElementKind.text`.
- `IndexSet(integer: 2)` — an `IndexSet` value (a set of integer indices) holding just `2`. SwiftUI's `onMove` hands you the moved rows as an `IndexSet`. Closest TS analogue is a `Set<number>`.
- `reorder(frontFirst:from:to:)` — argument labels read like prose: "reorder, front-first list `[c,b,a]`, from index 2, to 0." TS has no labels — positional args with a clarifying comment.
- `XCTAssertEqual(a.order, 2, "msg")` — the trailing string is the failure message shown if it fails; Jest passes it differently (3rd arg or `// comment`).

### `testReorderMovesFrontElementToBack`
The mirror: drag the front element `c` (display index 0) to the back (`to: 3`). Display becomes `[b, a, c]`, so `c.order == 0`, `a.order == 1`, `b.order == 2`. Note SwiftUI's move uses a `to:` index one past the end (`3`) to mean "after the last row."

```swift
SlideLayers.reorder(frontFirst: [c, b, a], from: IndexSet(integer: 0), to: 3)
XCTAssertEqual(c.order, 0, "moved-to-back element gets order 0")
```

**TypeScript equivalent (Jest)**

```ts
SlideLayers.reorder([c, b, a], new Set([0]), 3);   // to:3 = "after the last row"
expect(c.order).toEqual(0);   // "moved-to-back element gets order 0"
```

### `testRendererDrawsElementsInLayerOrder` `throws`
Two opaque full-slide shapes, one black and one white. Rendered with `elements: [black, white]` (back-to-front), the **white** one is drawn last so the center reads near-white (`centerRed > 200`). Swapping to `[white, black]` makes the center near-black (`centerRed < 60`). This proves the single-pass renderer honors element order across *all* kinds, not just within a layer. Uses the private `centerRed` helper that reads the red channel of the center pixel from a raw RGBA buffer.

```swift
let whiteOnTop = RenderableSlide(backgroundColorHex: "#222222", elements: [black, white])
let a = try XCTUnwrap(SlideRenderer.makeImage(whiteOnTop, pixelSize: size))
XCTAssertGreaterThan(centerRed(a), 200, "white shape on top → white center")
XCTAssertLessThan(centerRed(b), 60, "black shape on top → black center")
```

**TypeScript equivalent (Jest)**

```ts
const whiteOnTop = new RenderableSlide({ backgroundColorHex: "#222222", elements: [black, white] });
// XCTUnwrap: makeImage returns CGImage|null — assert non-null, then use it.
const a = SlideRenderer.makeImage(whiteOnTop, size);
expect(a).not.toBeNull();
expect(centerRed(a!)).toBeGreaterThan(200);   // "white shape on top → white center"
expect(centerRed(b!)).toBeLessThan(60);       // "black shape on top → black center"
```

**Swift syntax:**
- `try XCTUnwrap(...)` — `makeImage` returns `CGImage?` (optional); `XCTUnwrap` fails the test if `nil` and otherwise returns the unwrapped image. `try` because it can throw. TS: `not.toBeNull()` then use `a!`.

### `testLayerNameForEachKind`
`SlideElement.layerName` rules:
- Text uses its trimmed content (`"  Amazing grace  "` → `"Amazing grace"`).
- Blank/whitespace text falls back to `"Text"`.
- An image uses its `imageFilename` (`"logo.png"`).
- Shapes use a friendly type name: `"Rectangle"`, `"Ellipse"`, `"Rounded Rectangle"`.

Catches an empty layer row, or a shape showing a raw enum name.

```swift
let rect = SlideElement(kind: .shape); rect.shapeType = .rectangle
XCTAssertEqual(rect.layerName, "Rectangle")
let ellipse = SlideElement(kind: .shape); ellipse.shapeType = .ellipse
XCTAssertEqual(ellipse.layerName, "Ellipse")
```

**TypeScript equivalent (Jest)**

```ts
const rect = new SlideElement({ kind: SlideElementKind.shape });
rect.shapeType = ShapeType.rectangle;
expect(rect.layerName).toEqual("Rectangle");
const ellipse = new SlideElement({ kind: SlideElementKind.shape });
ellipse.shapeType = ShapeType.ellipse;
expect(ellipse.layerName).toEqual("Ellipse");
```

**Swift syntax:**
- `let rect = ...; rect.shapeType = ...` — two statements on one line separated by `;`. Swift usually omits semicolons; they're only needed to share a line.
- `.shape` / `.rectangle` / `.ellipse` — enum-case shorthand (`SlideElementKind.shape`, `ShapeType.rectangle`, …) with the type inferred from context.

## How it connects

Exercises `SlideLayers.reorder`, the shared `SlideRenderer.makeImage`, and `SlideElement.layerName` / `shapeType` / `imageFilename`. Uses `RenderableElement` and `RenderableSlide` value snapshots to feed the renderer.

## What it does NOT cover

The actual drag-to-reorder interaction in the Layers panel, live re-rendering as you drag, and selection highlighting are hand-verified in the app. This suite covers the reorder math, the z-order rendering rule, and the label strings.

## Glossary (Swift → TS/Jest/Node)

- **`final class FooTests: XCTestCase`** → `describe("Foo", ...)`.
- **`func testX()` / `throws`** → `it("x", ...)`; `throws` means a thrown error fails the test.
- **`try XCTUnwrap(x)`** → assert non-null, then use the value.
- **`IndexSet(integer:)`** → a set of integer indices; `// analogy:` the source index of a list-move event (`Set<number>`).
- **Argument labels (`reorder(frontFirst:from:to:)`)** → no TS equivalent; positional args with a clarifying comment.
- **`.shape` / `.rectangle` (enum shorthand)** → `EnumName.case` with the type inferred.
- **`;` on a line** → only needed to put two statements on one line (Swift omits it otherwise).
- **`XCTAssertEqual(a, b, "msg")`** → `toEqual` with a failure label.
- **`RenderableSlide` / `RenderableElement`** → immutable value snapshots fed to the renderer (no live model references).
