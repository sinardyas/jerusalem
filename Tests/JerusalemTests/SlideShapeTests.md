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

```swift
let element = SlideElement(kind: .shape, order: 0)
element.shapeType = .ellipse
element.fillColorHex = "#FF0000"
element.cornerRadius = 24
let snapshot = RenderableElement(element)
XCTAssertEqual(snapshot.shapeType, .ellipse)
XCTAssertEqual(snapshot.cornerRadius, 24, accuracy: 1e-9)
```

**TypeScript equivalent (Jest)**

```ts
const element = new SlideElement({ kind: SlideElementKind.shape, order: 0 });
element.shapeType = ShapeType.ellipse;
element.fillColorHex = "#FF0000";
element.cornerRadius = 24;
const snapshot = new RenderableElement(element);
expect(snapshot.shapeType).toEqual(ShapeType.ellipse);
expect(snapshot.cornerRadius).toBeCloseTo(24);
```

**Swift syntax:**
- `SlideElement(kind: .shape, order: 0)` — an initializer call (no `new`); `.shape` is enum-case shorthand for `SlideElementKind.shape`, the type inferred from the `kind:` parameter.
- `RenderableElement(element)` — an initializer with one positional argument (no label); maps to `new RenderableElement(element)`.
- `accuracy: 1e-9` — float-tolerant equality (Jest `toBeCloseTo`).

### `testUnknownShapeAndKindRawFallBackSafely`
`SlideElementKind(rawValue: "bogus")` and `ShapeType(rawValue: "bogus")` both return `nil` (no crash on bad stored data), and a fresh shape element defaults to `.rectangle`. This is the "follow the `…Raw: String` enum convention" safety check.

```swift
XCTAssertNil(ShapeType(rawValue: "bogus"))
XCTAssertEqual(SlideElement(kind: .shape, order: 0).shapeType, .rectangle)
```

**TypeScript equivalent (Jest)**

```ts
// A string-backed enum's "from raw" returns null for an unknown string.
expect(ShapeType.fromRaw("bogus")).toBeNull();
expect(new SlideElement({ kind: SlideElementKind.shape, order: 0 }).shapeType)
  .toEqual(ShapeType.rectangle);
```

**Swift syntax:**
- `ShapeType(rawValue: "bogus")` — a string-backed `enum` (`enum ShapeType: String`) gets a *failable initializer* `init?(rawValue:)` for free: it returns the matching case, or `nil` if the string isn't a valid case. There's no built-in TS equivalent — you'd write a `fromRaw` lookup that returns `null`. This is the safety net behind the project's "store enums as a `…Raw: String`" convention.

### `testShapeRendersDistinctPixels` `throws`
A white rectangle covering the middle 60% of a black slide must leave `> 1000` non-black pixels. Proves shapes render through the shared path. Uses the `nonBackgroundPixelCount` helper (draw to RGBA buffer, count bright pixels).

```swift
let image = try XCTUnwrap(
    SlideRenderer.makeImage(slide, pixelSize: CGSize(width: 200, height: 200)))
XCTAssertGreaterThan(nonBackgroundPixelCount(image), 1000)
```

**TypeScript equivalent (Jest)**

```ts
// XCTUnwrap: makeImage returns CGImage|null — assert non-null, then use it.
const image = SlideRenderer.makeImage(slide, { width: 200, height: 200 });
expect(image).not.toBeNull();
expect(nonBackgroundPixelCount(image!)).toBeGreaterThan(1000);
```

### `testEllipseLeavesBoundingBoxCornersBackground` `throws`
A full-bleed white ellipse must be filled white at the center (`center.r > 200`) but black at a near-corner pixel `(2,2)` (`corner.r < 40`), because an ellipse inscribed in a box doesn't touch the corners. This proves it's really an ellipse, not a rectangle. Uses the `pixelRGB` helper to sample exact pixels.

```swift
let center = pixelRGB(image, x: 50, y: 50)
let corner = pixelRGB(image, x: 2, y: 2)
XCTAssertGreaterThan(center.r, 200, "Ellipse center should be filled white")
XCTAssertLessThan(corner.r, 40, "Ellipse must leave its bounding-box corner black")
```

**TypeScript equivalent (Jest)**

```ts
const center = pixelRGB(image, 50, 50);
const corner = pixelRGB(image, 2, 2);
expect(center.r).toBeGreaterThan(200);   // "Ellipse center should be filled white"
expect(corner.r).toBeLessThan(40);       // "Ellipse must leave its bounding-box corner black"
```

**Swift syntax:**
- `pixelRGB(image, x: 50, y: 50)` — `image` is positional, `x:`/`y:` are labeled. The helper returns a private `struct RGB { let r: Int; let g: Int; let b: Int }` — a tiny immutable record (its `let` fields are read-only), like a TS `{ r, g, b }` object.

### `testShapeBorderUsesStrokeFields` `throws`
A small black rounded-rect with a thick white stroke (`hasStroke`, `strokeColorHex`, `strokeWidth`) must still render with `> 50` non-background pixels — the border path doesn't crash and adds visible pixels. This is a smoke-level check that stroked shapes work.

```swift
var element = shapeElement(.roundedRectangle, fill: "#000000", frame: (0.3, 0.3, 0.4, 0.4))
element.hasStroke = true
element.strokeColorHex = "#FFFFFF"
element.strokeWidth = 6
```

**TypeScript equivalent (Jest)**

```ts
const element = shapeElement(ShapeType.roundedRectangle, "#000000", [0.3, 0.3, 0.4, 0.4]);
element.hasStroke = true;
element.strokeColorHex = "#FFFFFF";
element.strokeWidth = 6;
```

**Swift syntax:**
- `var element = …` — `var` is a *mutable* binding (vs. `let`, which is constant/`const`). Here it's mutated below, so it must be `var`. Roughly `let`/`const` in JS, but the rule is reversed: Swift's `let` ≈ JS `const`, Swift's `var` ≈ JS `let`.
- `frame: (0.3, 0.3, 0.4, 0.4)` — a *tuple* (a fixed-size, ordered group of values). The helper's signature is `(Double, Double, Double, Double)`. TS has no tuples-with-labels here, so a `[number, number, number, number]` array works.

### `testShapeFieldsPersistAcrossContexts` `@MainActor throws`
Writes an `Item` → `Slide` → shape `SlideElement` (`.roundedRectangle`, fill `#12AB34`, corner radius `18`) to a real on-disk store and `save()`s. Reopens a fresh `ModelContainer` + `ModelContext`, re-fetches, and asserts all four shape fields survived. The `addTeardownBlock` deletes the `.store`/`-wal`/`-shm` files.

```swift
let configuration = ModelConfiguration(schema: Persistence.schema, url: url)
do {
    let container = try ModelContainer(for: Persistence.schema, configurations: configuration)
    let context = ModelContext(container)
    // ... insert item + slide + shape element ...
    context.insert(item)
    try context.save()
}
let container = try ModelContainer(for: Persistence.schema, configurations: configuration)
let context = ModelContext(container)
let items = try context.fetch(FetchDescriptor<Item>())
let item = try XCTUnwrap(items.first)
```

**TypeScript equivalent (Jest)**

```ts
// analogy: ModelContainer/Configuration ≈ a SQLite/Prisma DB at `url`.
const configuration = { schema: Persistence.schema, url };
{
  const container = await openDb(configuration);   // analogy: new ModelContainer
  const context = container.newContext();          // analogy: new ModelContext
  // ... insert item + slide + shape element ...
  context.insert(item);
  await context.save();
}
const container = await openDb(configuration);
const context = container.newContext();
const items = await context.fetch(Item);           // analogy: FetchDescriptor<Item>
const item = items[0];
expect(item).not.toBeNull();                        // XCTUnwrap(items.first)
```

**Swift syntax:**
- `@MainActor` — pins the function to the main thread (SwiftData requirement); no JS analogue.
- `do { … }` — here it's a plain scoping block (not a `try`/`catch`): the inner `container`/`context` deallocate at the closing brace, so the second open reads from a *fresh* connection — proving data persisted to disk, not just held in memory. (A standalone `{ }` block in JS.)
- `try context.save()` — `save` can throw; `try` propagates the error to the test (which fails). Like `await context.save()` where a rejection fails the test.
- `FetchDescriptor<Item>()` — a typed query for `Item` rows; `<Item>` is a generic type parameter.

## How it connects

Exercises the `SlideElement` shape fields (`shapeType`, `fillColorHex`, `cornerRadius`), the `SlideElementKind` / `ShapeType` enums, the `RenderableElement` snapshot, the shared `SlideRenderer.makeImage`, and the SwiftData schema (`Persistence.schema`, `Slide`, `Item`).

## What it does NOT cover

Adding a shape from the toolbar, dragging/resizing it on the canvas, and the shape inspector controls are interactive and verified by running the app (noted in the file's own header).

## Glossary (Swift → TS/Jest/Node)

- **`final class FooTests: XCTestCase`** → `describe("Foo", ...)`.
- **`func testX() throws`** → `it("x", ...)`; `throws` means a thrown error fails the test.
- **`@MainActor`** → run on the main thread (SwiftData); no JS equivalent.
- **`try XCTUnwrap(x)`** → assert non-null, then use the value.
- **`let` vs `var`** → Swift `let` ≈ JS `const`; Swift `var` ≈ JS `let` (mutable).
- **Enum `init?(rawValue:)`** → a string→enum lookup that returns `null` on an unknown string (the `…Raw: String` safety net).
- **`.shape` / `.ellipse` (enum shorthand)** → `EnumName.case` with the type inferred.
- **Tuple `(Double, Double, Double, Double)`** → a fixed-size group; modeled as a `[number, number, number, number]` array.
- **`struct RGB { let r; let g; let b }`** → an immutable record `{ r, g, b }`.
- **`do { }` (plain block)** → a scoping `{ }` block; here it forces the DB connection to close so the re-open proves persistence.
- **`accuracy:`** → `toBeCloseTo`.
- **`ModelContainer` / `ModelConfiguration` / `ModelContext` / `FetchDescriptor`** → DB connection / config / session / typed query (`// analogy:` Prisma-style ORM).
- **`addTeardownBlock { }`** → an inline `afterEach`.
