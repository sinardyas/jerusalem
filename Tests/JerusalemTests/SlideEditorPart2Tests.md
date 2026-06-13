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

**TypeScript equivalent (Jest)**

```ts
expect(InspectorTab.onSelectionChange(true)).toEqual(InspectorTab.format);
expect(InspectorTab.allCases.map(t => t.title)).toEqual(["Format", "Arrange", "Slide"]);
```

**Swift syntax:**
- `InspectorTab.onSelectionChange(hasSelection: true)` — Swift labels arguments at the call site. `hasSelection:` is the parameter's *external* name; in TS it's just a positional `true`.
- `.format` — leading-dot shorthand for an `enum` case. Because Swift infers the type from context, `InspectorTab.format` shortens to `.format`. No JS equivalent — you write the full `InspectorTab.format`.
- `.allCases` — an array of every case, free when an `enum` conforms to `CaseIterable`. Like a hand-written `Object.values(InspectorTab)`.
- `.map(\.title)` — `\.title` is a *key-path*: a first-class reference to the `title` property, used here as the map transform. Equivalent to `t => t.title`.

### `testCanvasZoomClampsAndApplies`
`CanvasZoomMath` clamps zoom to `0.5...2.0`, applies a pinch magnification (`applying(magnify:to:)`), and applies a ⌘-scroll delta (`applying(scroll:to:)`), always clamped. Catches runaway zoom from an aggressive pinch or scroll.

```swift
XCTAssertEqual(CanvasZoomMath.applying(magnify: 5, to: 1.0), 2.0, accuracy: 1e-9)  // clamps
```

**TypeScript equivalent (Jest)**

```ts
expect(CanvasZoomMath.applying(5, 1.0)).toBeCloseTo(2.0);  // clamps
```

**Swift syntax:**
- `0.5...2.0` — a *closed range* literal (both ends inclusive). In JS you'd express clamping with `Math.min(Math.max(x, 0.5), 2.0)`; there's no range literal.
- `accuracy: 1e-9` — float-tolerant compare. Floats rarely equal exactly, so a tiny epsilon is allowed. Jest's `toBeCloseTo` is the analogue.

### `testJustifyAlignmentRoundTripsThroughSnapshot`
A `SlideElement` with `.justified` alignment copies that value into its `RenderableElement` snapshot. Catches a new alignment case being dropped on the way to the renderer.

```swift
let element = SlideElement(kind: .text, order: 0, text: "Hi")
element.alignment = .justified
let snapshot = RenderableElement(element)
XCTAssertEqual(snapshot.alignment, .justified)
```

**TypeScript equivalent (Jest)**

```ts
const element = new SlideElement({ kind: SlideElementKind.text, order: 0, text: "Hi" });
element.alignment = TextAlignment.justified;
const snapshot = new RenderableElement(element);
expect(snapshot.alignment).toEqual(TextAlignment.justified);
```

**Swift syntax:**
- `SlideElement(kind: .text, order: 0, text: "Hi")` — calling an initializer (no `new` keyword in Swift; the type name *is* the constructor call). TS uses `new`.
- `RenderableElement(element)` — an initializer taking a positional argument (this one has no external label). Maps to `new RenderableElement(element)`.

### `testTypographyDepthFieldsCopyIntoRenderable`
Sets eight deep-styling fields on a model (line spacing, letter spacing, stroke width/color, shadow blur/offset/color, underline) and asserts every one copies into the `RenderableElement`. The renderer only ever sees the snapshot, so a missed field would silently never render.

```swift
let element = SlideElement(kind: .text, order: 0, text: "Hi")
element.strokeColorHex = "#FF0000"
element.shadowColorHex = "#00FF00CC"
element.isUnderlined = true
let snapshot = RenderableElement(element)
XCTAssertEqual(snapshot.strokeColorHex, "#FF0000")
XCTAssertTrue(snapshot.isUnderlined)
```

**TypeScript equivalent (Jest)**

```ts
const element = new SlideElement({ kind: SlideElementKind.text, order: 0, text: "Hi" });
element.strokeColorHex = "#FF0000";
element.shadowColorHex = "#00FF00CC";
element.isUnderlined = true;
const snapshot = new RenderableElement(element);
expect(snapshot.strokeColorHex).toEqual("#FF0000");
expect(snapshot.isUnderlined).toBe(true);
```

### `testUnderlinedTextRasterizesExtraPixels` `throws`
A genuine pixel proof: render `"HELLO"` with and without underline, then count non-black pixels. The underlined image must have *more* (the underline fills extra rows). Uses the private `nonBlackPixelCount` helper that draws the `CGImage` into a raw RGBA buffer and counts pixels above a brightness threshold.

```swift
XCTAssertGreaterThan(nonBlackPixelCount(a), nonBlackPixelCount(b))
```

**TypeScript equivalent (Jest)**

```ts
expect(nonBlackPixelCount(a)).toBeGreaterThan(nonBlackPixelCount(b));
```

### `testGradientBackgroundDiffersAtTopVsBottom` `throws`
Renders a `.gradient` background (red→blue, angle 90°) and reads two pixels — top vs bottom. They must differ in color, which is the whole point of a gradient. Catches a gradient that collapsed to a flat fill.

```swift
let slide = RenderableSlide(
    backgroundKind: .gradient,
    backgroundColorHex: "#FF0000",
    elements: [],
    gradientHex2: "#0000FF",
    gradientAngle: 90)
let image = try XCTUnwrap(
    SlideRenderer.makeImage(slide, pixelSize: CGSize(width: 100, height: 100)))
XCTAssertFalse(top.r == bottom.r && top.g == bottom.g && top.b == bottom.b)
```

**TypeScript equivalent (Jest)**

```ts
const slide = new RenderableSlide({
  backgroundKind: BackgroundKind.gradient,
  backgroundColorHex: "#FF0000",
  elements: [],
  gradientHex2: "#0000FF",
  gradientAngle: 90,
});
// XCTUnwrap: makeImage returns CGImage|null — assert non-null, then use it.
const image = SlideRenderer.makeImage(slide, { width: 100, height: 100 });
expect(image).not.toBeNull();
expect(top.r === bottom.r && top.g === bottom.g && top.b === bottom.b).toBe(false);
```

**Swift syntax:**
- `try XCTUnwrap(...)` — `makeImage` returns an *optional* (`CGImage?`). `XCTUnwrap` fails the test if it's `nil`, otherwise hands back the unwrapped value. `try` is required because it can throw. In TS: `expect(x).not.toBeNull()` then use `x!`.
- `CGSize(width: 100, height: 100)` — a `struct` initializer with labeled fields; like `{ width: 100, height: 100 }`.
- `&&` — same boolean AND as JS.

### `testColorBackgroundKindFillsTheWholeSlide` `throws`
The contrast case: a `.color` background must be *uniform* — top and bottom pixels both read pure red `(255, 0, 0)`. Catches a solid background accidentally bleeding a gradient.

```swift
XCTAssertEqual(top.r, 255); XCTAssertEqual(top.g, 0); XCTAssertEqual(top.b, 0)
XCTAssertEqual(bottom.r, top.r)
```

**TypeScript equivalent (Jest)**

```ts
expect(top.r).toEqual(255); expect(top.g).toEqual(0); expect(top.b).toEqual(0);
expect(bottom.r).toEqual(top.r);
```

**Swift syntax:**
- `;` — Swift normally omits semicolons; here two statements share a line, so they're separated explicitly. Optional in JS too.

### `testThemeCopyCapturesElementTypography`
`Theme.copy(from: element)` (the "Set as default" action) must absorb every typography field from an element into the theme. Seventeen assertions confirm font, color, alignment, bold/italic/underline, shadow/stroke toggles, autofit, and all the depth fields. Catches "Set as default" forgetting a field.

```swift
theme.copy(from: element)
XCTAssertEqual(theme.fontName, "Georgia")
XCTAssertEqual(theme.alignment, .trailing)
XCTAssertFalse(theme.isBold)
```

**TypeScript equivalent (Jest)**

```ts
theme.copyFrom(element);
expect(theme.fontName).toEqual("Georgia");
expect(theme.alignment).toEqual(TextAlignment.trailing);
expect(theme.isBold).toBe(false);
```

**Swift syntax:**
- `theme.copy(from: element)` — the method is named `copy`, with an argument *label* `from`. Reads like a sentence ("copy from element"). In TS the label disappears into the method name or a positional arg: `theme.copyFrom(element)`.

### `testThemeAppliedAfterCopyProducesMatchingElement`
The round-trip's other half: after `theme.copy(from:)`, calling `theme.apply(to: freshElement)` must reproduce the same typography on a brand-new element. Proves copy and apply are symmetric.

```swift
theme.copy(from: source)
let fresh = SlideElement(kind: .text, order: 0, text: "New")
theme.apply(to: fresh)
XCTAssertEqual(fresh.fontName, "Menlo")
```

**TypeScript equivalent (Jest)**

```ts
theme.copyFrom(source);
const fresh = new SlideElement({ kind: SlideElementKind.text, order: 0, text: "New" });
theme.applyTo(fresh);
expect(fresh.fontName).toEqual("Menlo");
```

### `testNewSlideElementAndSlideFieldsPersistAcrossContexts` `@MainActor throws`
The persistence smoke test. It builds a real on-disk store (not in-memory), writes an `Item` with a `4:3` aspect ratio, a `Slide` with a gradient background, and a `SlideElement` with depth styling, then `save()`s. It opens a **fresh** `ModelContainer` + `ModelContext` against the same file and re-fetches, asserting every field survived. The `addTeardownBlock` cleans up the `.store`, `-wal`, and `-shm` files afterward.

```swift
let configuration = ModelConfiguration(schema: Persistence.schema, url: url)
let container = try ModelContainer(for: Persistence.schema, configurations: configuration)
let context = ModelContext(container)
// ... insert + save ...
let items = try context.fetch(FetchDescriptor<Item>())
let item = try XCTUnwrap(items.first)
XCTAssertEqual(item.aspectRatio, "4:3")
```

**TypeScript equivalent (Jest)**

```ts
// analogy: ModelContainer/ModelConfiguration ≈ opening a SQLite/Prisma DB at `url`.
const configuration = { schema: Persistence.schema, url };
const container = await openDb(configuration);   // analogy: new ModelContainer
const context = container.newContext();           // analogy: new ModelContext
// ... insert + await context.save() ...
const items = await context.fetch(Item);          // analogy: FetchDescriptor<Item>
const item = items[0];
expect(item).not.toBeNull();                       // XCTUnwrap(items.first)
expect(item.aspectRatio).toEqual("4:3");
```

```swift
addTeardownBlock {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
    }
}
```

**TypeScript equivalent (Jest)**

```ts
// addTeardownBlock ≈ registering an afterEach inline, mid-test.
afterEach(() => {
  for (const suffix of ["", "-wal", "-shm"]) {
    try { fs.rmSync(url.path + suffix); } catch { /* try? — ignore failure */ }
  }
});
```

**Swift syntax:**
- `@MainActor` — an attribute pinning this function to the main thread/actor (SwiftData needs it). No JS analogue; everything is single-threaded there.
- `ModelConfiguration` / `ModelContainer` / `ModelContext` — SwiftData's persistence stack: configuration (where/how the store lives), container (the store itself), context (a working session you fetch/insert/save through). Think DB config → DB connection → transaction/session.
- `FetchDescriptor<Item>()` — a typed query for `Item` rows; the `<Item>` is a generic type parameter (`fetch<Item>()`).
- `addTeardownBlock { ... }` — the `{ ... }` is a *trailing closure* (an anonymous function passed as the last argument). Like passing an arrow function.
- `for suffix in [...]` — `for…in` over an array, same as JS `for…of`.
- `try?` — "try, but turn any thrown error into `nil` and move on." Here it just ignores a failed delete. Like a `try { } catch {}` that swallows.
- `FileManager.default` — the shared file-system API singleton, like Node's `fs`.
- `URL(fileURLWithPath:)` — builds a file URL from a path string.

## How it connects

Exercises `Item.aspectRatioValue`, `InspectorTab`, `CanvasZoomMath`, `SlideElement`, `RenderableElement`, `RenderableSlide`, `Theme.copy/apply`, the shared `SlideRenderer.makeImage`, and the SwiftData schema (`Persistence.schema`, `ModelContainer`, `Slide`).

## What it does NOT cover

The interactive UX — actually dragging with snap, pinch-zooming with a trackpad, clicking the segmented inspector bar, picking gradient stops in a color well — is hand-verified on real hardware (`docs/DRESS-REHEARSAL.md` §10.1–§10.6). These tests cover the math, the snapshots, the pixels, and the persistence.

## Glossary (Swift → TS/Jest/Node)

- **`final class FooTests: XCTestCase`** → `describe("Foo", ...)`. `final` means "no subclassing"; the `: XCTestCase` makes it a test suite.
- **`func testX() throws`** → `it("x", ...)`. Methods starting with `test` auto-run; `throws` means a thrown error fails the test.
- **`@MainActor`** → run on the main thread; no JS equivalent (JS is single-threaded).
- **Optionals (`T?`, `if let`, `guard let`, `??`, `?.`, `try?`)** → `T | null`; `??` ≈ `??`/`||`; `?.` ≈ optional chaining; `try?` ≈ swallow-error-to-null.
- **`try XCTUnwrap(x)`** → assert non-null, then use the value.
- **Closures / trailing closure / `$0`** → arrow functions; `{ ... }` after a call is the last arg; `$0` is the first implicit parameter.
- **`enum` + `.case` shorthand** → a union of constants; `.format` is `EnumName.format` with the type inferred.
- **`.allCases` (CaseIterable)** → `Object.values(Enum)`.
- **Key-path `\.title`** → `x => x.title`.
- **Range `0.5...2.0`** → an inclusive range; no JS literal (use `min`/`max`).
- **`accuracy:`** → `toBeCloseTo` — float-tolerant equality.
- **`ModelContainer` / `ModelConfiguration` / `ModelContext` / `FetchDescriptor`** → DB connection / DB config / session / typed query (`// analogy:` Prisma-style ORM).
- **`addTeardownBlock { }`** → an inline `afterEach`.
- **`FileManager` / `URL`** → Node's `fs` / a file path.
