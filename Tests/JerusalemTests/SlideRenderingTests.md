# `SlideRenderingTests.swift`

> The Phase 2 gate: proves the one shared `SlideRenderer` produces an image at the requested pixel size, auto-fits oversized text, actually draws glyphs, honors different background kinds (color/image/video), and renders different font families distinctly.

**Location:** `Tests/JerusalemTests/SlideRenderingTests.swift`
**Role:** XCTest unit tests

## What it does (plain English)

`SlideRenderer.makeImage` is *the* single code path that turns a slide into a `CGImage` — the same path drives grid thumbnails, the inspector preview, and the live audience screen. If it's wrong, everything is wrong. This file is the headless safety net for that path.

The strategy throughout is "render to an image, then inspect real pixels." Several private helpers draw a `CGImage` into a flat RGBA byte buffer and then count or sample pixels — counting bright (non-black) pixels to prove text was drawn, counting fully-transparent pixels to prove a motion background lets the video show through, or reading the center pixel's RGB to prove an image background was painted.

There are also two pure-math tests around auto-fit: `fittedFontSize` should shrink a font when the text overflows its box, and leave it alone when it already fits.

## XCTest you'll meet in this file

| XCTest API | Jest equivalent |
| --- | --- |
| `func testFoo()` / `func testFoo() throws` | `it('foo', ...)` |
| `XCTAssertNotNil(x)` | `expect(x).not.toBeNull()` |
| `XCTAssertEqual(a, b)` / `(a, b, accuracy:)` | `expect(a).toEqual(b)` / `toBeCloseTo` |
| `XCTAssertLessThan / GreaterThan(a, b)` | numeric comparisons |
| `XCTAssertNotEqual(a, b, "msg")` | `expect(a).not.toEqual(b)` |
| `try XCTUnwrap(optional)` | assert-non-null-and-return |
| `addTeardownBlock { ... }` | inline `afterEach` cleanup |

## The tests, one by one

### `testRendersImageAtRequestedPixelSize`
Renders a slide at `320×180` and asserts the result is non-nil and exactly `320×180`. The bedrock test: the renderer honors the requested size. Catches a rounding/DPI bug that produces an off-size image.

```swift
let image = SlideRenderer.makeImage(slide, pixelSize: CGSize(width: 320, height: 180))
XCTAssertNotNil(image)
XCTAssertEqual(image?.width, 320)
XCTAssertEqual(image?.height, 180)
```

**TypeScript equivalent (Jest)**

```ts
const image = SlideRenderer.makeImage(slide, { width: 320, height: 180 });
expect(image).not.toBeNull();
expect(image?.width).toEqual(320);
expect(image?.height).toEqual(180);
```

**Swift syntax:**
- `CGSize(width: 320, height: 180)` — a `struct` initializer with labeled fields; like `{ width: 320, height: 180 }`.
- `image?.width` — optional chaining: `makeImage` returns `CGImage?`, so `?.width` reads `.width` only if the image isn't `nil`. Same as TS `image?.width`.

### `testAutoFitShrinksOversizedText`
Calls `SlideRenderer.fittedFontSize` with a long string in a small box at base size `200`. The returned size must be `< 200` — auto-fit shrank it. Catches text overflowing its box on screen.

```swift
let longText = String(repeating: "Amazing grace how sweet the sound ", count: 6)
let fitted = SlideRenderer.fittedFontSize(
    text: longText, fontName: "Avenir Next", isBold: true, isItalic: false,
    baseSize: 200, boxSize: box)
XCTAssertLessThan(fitted, 200)
```

**TypeScript equivalent (Jest)**

```ts
const longText = "Amazing grace how sweet the sound ".repeat(6);
const fitted = SlideRenderer.fittedFontSize({
  text: longText, fontName: "Avenir Next", isBold: true, isItalic: false,
  baseSize: 200, boxSize: box,
});
expect(fitted).toBeLessThan(200);
```

**Swift syntax:**
- `String(repeating: "…", count: 6)` — an initializer that repeats a string N times; the JS equivalent is `"…".repeat(6)`.
- `fittedFontSize(text:fontName:…)` — every argument is labeled; TS models this as an options object.

### `testAutoFitLeavesFittingTextUnchanged`
The contrast: `"Hi"` at base size `40` in a big box stays exactly `40`. Catches auto-fit needlessly shrinking text that already fits.

```swift
XCTAssertEqual(fitted, 40, accuracy: 0.001)
```

**TypeScript equivalent (Jest)**

```ts
expect(fitted).toBeCloseTo(40, 3);   // accuracy 0.001 ≈ 3 decimal places
```

**Swift syntax:**
- `accuracy: 0.001` — float-tolerant equality with an explicit epsilon. Jest's `toBeCloseTo(x, digits)` is the analogue.

### `testStyledTextRasterizesPixels` `throws`
Renders white `"HELLO"` on black and counts non-black pixels (`nonBackgroundPixelCount`). There must be `> 200` of them — i.e. glyphs really got drawn. Catches the renderer producing an empty/blank image.

```swift
let image = try XCTUnwrap(
    SlideRenderer.makeImage(slide, pixelSize: CGSize(width: 480, height: 270)))
XCTAssertGreaterThan(nonBackgroundPixelCount(image), 200)
```

**TypeScript equivalent (Jest)**

```ts
// XCTUnwrap: makeImage returns CGImage|null — assert non-null, then use it.
const image = SlideRenderer.makeImage(slide, { width: 480, height: 270 });
expect(image).not.toBeNull();
expect(nonBackgroundPixelCount(image!)).toBeGreaterThan(200);
```

**Swift syntax:**
- `try XCTUnwrap(...)` — unwraps an optional (`CGImage?`); fails the test if `nil`. The pixel-counting helper then loops the RGBA buffer:

```swift
for index in stride(from: 0, to: data.count, by: 4)
where data[index] > 40 || data[index + 1] > 40 || data[index + 2] > 40 {
    count += 1
}
```

**TypeScript equivalent (Jest)**

```ts
for (let index = 0; index < data.length; index += 4) {
  if (data[index] > 40 || data[index + 1] > 40 || data[index + 2] > 40) {
    count += 1;
  }
}
```

**Swift syntax:**
- `stride(from: 0, to: data.count, by: 4)` — produces `0, 4, 8, …` up to but not including `data.count`. It's Swift's way of stepping a loop by 4 (here, one RGBA pixel = 4 bytes). JS: a `for` with `index += 4`.
- `for … where <cond> { }` — a `for-in` loop with a built-in filter; the body runs only when `where` is true. Like a JS `for` with an `if` guard inside.

### `testMotionBackgroundLeavesTransparentBackground` `throws`
A slide with a `.video` background (a `VideoCue` pointing at a non-existent file) must render with **transparent** background pixels, so the live video layer underneath shows through — `transparentPixelCount > 0`. A normal solid-color slide must be fully opaque (`transparentPixelCount == 0`). This is how still rendering and live video compose without fighting. The helper counts pixels whose alpha byte (`data[index + 3]`) is `0`.

```swift
let cue = VideoCue(url: URL(fileURLWithPath: "/tmp/none.mov"),
                   loops: true, muted: true, endBehavior: .hold)
let motion = RenderableSlide(backgroundKind: .video,
                             backgroundColorHex: "#1E3A8A",
                             elements: [textElement("Hi")], backgroundVideo: cue)
XCTAssertGreaterThan(transparentPixelCount(motionImage), 0)
XCTAssertEqual(transparentPixelCount(solidImage), 0)
```

**TypeScript equivalent (Jest)**

```ts
const cue = new VideoCue({
  url: fileURL("/tmp/none.mov"), loops: true, muted: true, endBehavior: EndBehavior.hold,
});
const motion = new RenderableSlide({
  backgroundKind: BackgroundKind.video, backgroundColorHex: "#1E3A8A",
  elements: [textElement("Hi")], backgroundVideo: cue,
});
expect(transparentPixelCount(motionImage)).toBeGreaterThan(0);
expect(transparentPixelCount(solidImage)).toEqual(0);
```

**Swift syntax:**
- `URL(fileURLWithPath: "/tmp/none.mov")` — builds a file URL from a path string (the file doesn't have to exist). Like Node's `pathToFileURL`.
- `endBehavior: .hold` — enum-case shorthand for `EndBehavior.hold`.

### `testImageBackgroundIsDrawn` `throws`
Writes a tiny solid-red PNG to a temp directory (via the `writeSolidPNG` helper using `NSBitmapImageRep`), points a slide's `backgroundImageURL` at it, renders, and reads the center pixel: red high (`> 150`), green/blue low (`< 90`). Proves an image background is actually painted rather than falling back to black. `addTeardownBlock` removes the temp directory.

```swift
let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("jx-img-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
```

**TypeScript equivalent (Jest)**

```ts
const directory = path.join(os.tmpdir(), `jx-img-${randomUUID()}`);
fs.mkdirSync(directory, { recursive: true });
// addTeardownBlock ≈ an afterEach registered inline.
afterEach(() => { try { fs.rmSync(directory, { recursive: true }); } catch {} });
```

**Swift syntax:**
- `FileManager.default.temporaryDirectory` — the system temp directory URL; like `os.tmpdir()`.
- `.appendingPathComponent("…\(UUID().uuidString)")` — appends a path segment; the `\(…)` is *string interpolation* (`${…}` in JS), and `UUID().uuidString` is a random UUID string (`randomUUID()`).
- `try FileManager.default.createDirectory(…, withIntermediateDirectories: true)` — make the dir and any parents (`mkdir -p`); `try` because it can throw.
- `addTeardownBlock { try? … }` — the `{ … }` is a *trailing closure* registered as cleanup; `try?` swallows a failed delete.

### `testDifferentFontFamiliesRenderDifferently` `throws`
A regression guard. The renderer once used `NSFont(name:)`, which returns `nil` for *family* names and silently fell back to the system font — so every family looked identical. This test renders the word `"Reading"` in `"Menlo"` and `"Georgia"` and asserts the raw byte arrays differ.

```swift
XCTAssertNotEqual(try render("Menlo"), try render("Georgia"),
                  "Different font families must produce different renders")
```

**TypeScript equivalent (Jest)**

```ts
expect(render("Menlo")).not.toEqual(render("Georgia"));
// message: "Different font families must produce different renders"
```

**Swift syntax:**
- `XCTAssertNotEqual(a, b, "msg")` — fails if `a == b`; the trailing string is the failure message. Note `render` is a *nested* function declared inside the test (Swift allows functions inside functions) — like an inner arrow function in JS.

## How it connects

Exercises the core production type `SlideRenderer` — `makeImage(_:pixelSize:)` and `fittedFontSize(...)`. Feeds it `RenderableSlide` / `RenderableElement` value snapshots and `VideoCue`. The pixel-inspection helpers use Core Graphics (`CGContext`, `CGImage`) and AppKit (`NSColor`, `NSBitmapImageRep`, `NSGraphicsContext`) directly.

## What it does NOT cover

This proves the *image* is correct in a headless buffer. It does **not** prove full-screen output looks right on a real external display, nor that live AVFoundation video plays back smoothly behind a motion background — those are hardware gates verified by running the app with a second display (per `CLAUDE.md` and `docs/DRESS-REHEARSAL.md`).

## Glossary (Swift → TS/Jest/Node)

- **`final class FooTests: XCTestCase`** → `describe("Foo", ...)`.
- **`func testX()` / `throws`** → `it("x", ...)`; `throws` means a thrown error fails the test.
- **`try XCTUnwrap(x)`** → assert non-null, then use the value.
- **Optionals (`T?`, `?.`)** → `T | null`, optional chaining.
- **`accuracy:`** → `toBeCloseTo` — float-tolerant equality.
- **`addTeardownBlock { }`** → an inline `afterEach`.
- **Trailing closure `{ … }` / `$0`** → arrow function as last arg; `$0` is the first implicit parameter.
- **String interpolation `\(x)`** → `${x}`.
- **`stride(from:to:by:)`** → a stepped loop (`for (i; i < n; i += step)`).
- **`for … where <cond>`** → a `for-in` with a built-in filter (loop + inner `if`).
- **`String(repeating:count:)`** → `"…".repeat(n)`.
- **`FileManager` / `URL` / `temporaryDirectory`** → Node's `fs` / a file path / `os.tmpdir()`.
- **`UUID().uuidString`** → `randomUUID()`.
