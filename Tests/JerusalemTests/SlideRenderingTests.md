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

### `testAutoFitShrinksOversizedText`
Calls `SlideRenderer.fittedFontSize` with a long string in a small box at base size `200`. The returned size must be `< 200` — auto-fit shrank it. Catches text overflowing its box on screen.

### `testAutoFitLeavesFittingTextUnchanged`
The contrast: `"Hi"` at base size `40` in a big box stays exactly `40`. Catches auto-fit needlessly shrinking text that already fits.

```swift
XCTAssertEqual(fitted, 40, accuracy: 0.001)
```

### `testStyledTextRasterizesPixels` `throws`
Renders white `"HELLO"` on black and counts non-black pixels (`nonBackgroundPixelCount`). There must be `> 200` of them — i.e. glyphs really got drawn. Catches the renderer producing an empty/blank image.

```swift
XCTAssertGreaterThan(nonBackgroundPixelCount(image), 200)
```

### `testMotionBackgroundLeavesTransparentBackground` `throws`
A slide with a `.video` background (a `VideoCue` pointing at a non-existent file) must render with **transparent** background pixels, so the live video layer underneath shows through — `transparentPixelCount > 0`. A normal solid-color slide must be fully opaque (`transparentPixelCount == 0`). This is how still rendering and live video compose without fighting. The helper counts pixels whose alpha byte (`data[index + 3]`) is `0`.

### `testImageBackgroundIsDrawn` `throws`
Writes a tiny solid-red PNG to a temp directory (via the `writeSolidPNG` helper using `NSBitmapImageRep`), points a slide's `backgroundImageURL` at it, renders, and reads the center pixel: red high (`> 150`), green/blue low (`< 90`). Proves an image background is actually painted rather than falling back to black. `addTeardownBlock` removes the temp directory.

### `testDifferentFontFamiliesRenderDifferently` `throws`
A regression guard. The renderer once used `NSFont(name:)`, which returns `nil` for *family* names and silently fell back to the system font — so every family looked identical. This test renders the word `"Reading"` in `"Menlo"` and `"Georgia"` and asserts the raw byte arrays differ.

```swift
XCTAssertNotEqual(try render("Menlo"), try render("Georgia"),
                  "Different font families must produce different renders")
```

## How it connects

Exercises the core production type `SlideRenderer` — `makeImage(_:pixelSize:)` and `fittedFontSize(...)`. Feeds it `RenderableSlide` / `RenderableElement` value snapshots and `VideoCue`. The pixel-inspection helpers use Core Graphics (`CGContext`, `CGImage`) and AppKit (`NSColor`, `NSBitmapImageRep`, `NSGraphicsContext`) directly.

## What it does NOT cover

This proves the *image* is correct in a headless buffer. It does **not** prove full-screen output looks right on a real external display, nor that live AVFoundation video plays back smoothly behind a motion background — those are hardware gates verified by running the app with a second display (per `CLAUDE.md` and `docs/DRESS-REHEARSAL.md`).
