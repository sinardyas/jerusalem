# `SlideRenderer.swift`

> The single, shared function that turns a slide snapshot into a bitmap image — the one rendering path behind thumbnails, the inspector preview, and the live audience screen.

**Location:** `Sources/Jerusalem/Rendering/SlideRenderer.swift`
**Role:** pure-logic namespace

## What it does (plain English)

This is the heart of the app's reliability promise. `SlideRenderer` is a caseless `enum` — a namespace of pure functions with no instances, like `export const SlideRenderer = { makeImage() {...} }` in JS. Its one public job is `makeImage`: hand it a `RenderableSlide` snapshot and a target pixel size, and it paints a finished bitmap (`CGImage`).

The reason there's *one* such function is consistency: if grid thumbnails, the inspector preview, and the live output all flow through the exact same code, then what the operator sees while editing is pixel-for-pixel what the audience will see. There is deliberately no second rendering path anywhere in the app.

Internally it works like a tiny drawing program. It creates an off-screen canvas (`CGContext`), paints the background (solid color, gradient, image, or transparent for video), then draws each element back-to-front: shapes, images, and text. Text drawing is where the real complexity lives — fonts resolved by family, optional bold/italic, stroke outlines, drop shadows, line spacing, letter spacing, and an "auto-fit" routine that shrinks the font until the text fits its box.

Because all coordinates in the snapshot are normalized (`0...1`) and the font sizes are relative to a 1920×1080 reference, the renderer multiplies everything by the real output size on the way in — so the same slide renders correctly at any resolution.

## Swift you'll meet in this file

| Swift | JS/TS meaning |
| --- | --- |
| `enum SlideRenderer { static func ... }` | A namespace of static functions — no instances exist |
| `static let referenceHeight: CGFloat = 1080` | A module constant; `CGFloat` is just a floating-point number for graphics |
| `CGContext` | A drawing canvas (Apple's Core Graphics) — you issue paint commands to it |
| `CGImage` | The finished bitmap produced from the canvas |
| `NSColor`, `NSImage`, `NSBezierPath`, `NSFont` | AppKit types: a color, an image, a vector path, a font |
| `NSAttributedString` | Styled text — a string plus per-range attributes (font, color, shadow…) |
| `guard let context = ... else { return nil }` | If construction fails, return `null` immediately |
| `switch slide.backgroundKind { case .video: ... }` | A `switch` over an enum; cases are exhaustive |
| `defer { ... }` | Run this block when the function exits, no matter how (like `try/finally`) |
| `context.translateBy / scaleBy` | Transform the canvas coordinate system (move/flip) |
| `0..<16` | A half-open range `0,1,...,15` — like a `for` loop bound |
| `?? .black` | Nullish coalescing — fall back to black if the hex parse returns `null` |

## Code walkthrough

### `makeImage` — the public entry point

```swift
static func makeImage(_ slide: RenderableSlide, pixelSize: CGSize) -> CGImage? {
    let width = max(1, Int(pixelSize.width.rounded()))
    let height = max(1, Int(pixelSize.height.rounded()))

    guard let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
```

It clamps the size to at least 1×1 and creates an RGBA off-screen bitmap canvas. If the OS can't make the canvas, it returns `nil` rather than crashing.

**Background pass** — different rules per kind:

```swift
switch slide.backgroundKind {
case .video:
    break  // leave transparent — the live video composites behind
case .image:
    context.setFillColor(NSColor.black.cgColor)  // black letterboxing
    context.fill(CGRect(origin: .zero, size: size))
case .color:
    let base = NSColor(hex: slide.backgroundColorHex) ?? .black
    context.setFillColor(base.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
case .gradient:
    drawGradient(slide: slide, in: context, size: size)
}
```

For a video background it paints nothing (transparent) so the actual looping video shows through. For an image background it paints black first so any letterboxing around an off-aspect photo looks intentional ("theatre, not bleed").

**Coordinate flip.** Core Graphics is bottom-left origin; the slide model is top-left. So it flips the canvas vertically once, then all drawing matches the normalized top-left coordinates:

```swift
context.translateBy(x: 0, y: size.height)
context.scaleBy(x: 1, y: -1)
```

It then activates an `NSGraphicsContext` (so AppKit text/image APIs draw into this canvas) and uses `defer` to restore the graphics state on the way out — guaranteed cleanup.

**Element pass.** Elements are pre-sorted back-to-front, and each is dispatched by kind:

```swift
let scale = size.height / referenceHeight
for element in slide.elements {
    switch element.kind {
    case .shape: drawShapeElement(element, in: size, scale: scale)
    case .image: drawImageElement(element, in: size)
    case .text:  draw(element, in: size, scale: scale)
    }
}
return context.makeImage()
```

`scale` is the bridge from the 1080-reference to the real output — every font size and corner radius gets multiplied by it. The comment notes there's no fixed shape→image→text layering; the Layers panel controls stacking via element order.

### `fittedFontSize` — auto-fit

```swift
static func fittedFontSize(...) -> CGFloat {
    let minSize = max(8, baseSize * 0.25)
    var fontSize = baseSize
    for _ in 0..<16 {
        let attributed = measuringString(...)
        let fitted = attributed.boundingRect(
            with: CGSize(width: boxSize.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        if fitted.height <= boxSize.height || fontSize <= minSize { break }
        let ratio = boxSize.height / fitted.height
        fontSize = max(minSize, fontSize * min(0.95, max(0.6, ratio)))
    }
    return fontSize
}
```

It measures the wrapped text height, and if it's too tall, multiplies the font down by a damped ratio (never less than 0.6× or more than 0.95× per step, clamped to a floor of 8pt or 25% of the base). It iterates at most 16 times — a bounded loop, so it can never hang. This is `static` and documented as "exposed for testing the auto-fit rule," so the math is unit-tested directly.

### Background drawing helpers

`drawGradient` builds a two-stop linear gradient and computes start/end points from `gradientAngle` so the gradient runs corner-to-corner at any angle; if a color is missing it falls back to a solid fill. `aspectFill` computes the rect to scale an image so it *covers* a box while keeping aspect ratio (cropping overflow).

### Element drawing

`drawImageElement` loads a per-element image and aspect-fills it into the element's normalized box — and crucially, a missing or unloadable file is a **silent no-op**:

```swift
guard let image = NSImage(contentsOf: url) else { return }
```

A deleted clip can't crash the renderer mid-service; the slide's other elements still draw.

`drawShapeElement` builds a rectangle / ellipse / rounded-rectangle path, fills it (defaulting to system blue if the hex is bad), and optionally strokes a border whose width scales like the font does. The corner radius is clamped so it can't exceed half the smaller side.

### Text drawing

`draw` computes the box, applies auto-fit if enabled, builds the styled string, then vertically centers the text block in its box before drawing:

```swift
let drawRect = CGRect(x: box.minX, y: box.minY + (box.height - textHeight) / 2,
                      width: box.width, height: textHeight)
attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin], context: nil)
```

`font(...)` is the careful part — the picker offers *family* names (like "Avenir Next"), but `NSFont(name:)` only accepts PostScript names. So it resolves the family through an `NSFontDescriptor` and applies bold/italic as symbolic traits, with layered fallbacks (drop the trait, then fall back to the system font) so an unknown family never produces blank text.

`styledString` assembles all the `NSAttributedString` attributes — color, paragraph style (alignment + line spacing), optional letter spacing (`.kern`, scaled for auto-fit), underline, stroke (a negative `.strokeWidth` means "fill *and* stroke"), and a drop shadow with scaled offset/blur. Line spacing math is subtle:

```swift
style.lineSpacing = max(0, fontSize * (lineSpacingMultiplier - 1.0))
```

AppKit's `lineSpacing` is *additional* leading, so it subtracts 1 from the multiplier before scaling — a 1.0 multiplier means zero extra spacing.

## How it connects

- **Input:** only `RenderableSlide` (the immutable snapshot). It never sees a SwiftData model — that's the value-snapshot invariant, and it's what makes "what you edit = what's on screen" true.
- **Called by:** `SlidePrewarmer.prewarm`, which is the only thing `RenderableSlideView` calls. So every on-screen slide — thumbnail, preview, and live output — funnels through this one `makeImage`.
- **Depends on:** `NSColor(hex:)` from `ColorHex.swift` for every color, plus `MediaStorage` for resolving image filenames to URLs.
- **The single-path invariant:** do not add a second way to turn a slide into pixels. Everything visual must go through here so the three surfaces stay identical.

## Gotchas / why it matters

- **Main thread only.** AppKit text drawing (`NSAttributedString.draw`, `NSFont`) requires the main thread. Callers drive it from a SwiftUI `.task`, which runs on the main actor.
- **Never crash mid-service.** Missing files, bad hex, and failed canvas creation all degrade gracefully (no-op, fallback color, or `nil`) — by design. Preserve that when editing.
- **Normalized in, pixels out.** All input geometry is `0...1` and fonts are at the 1080 reference; the `scale` factor converts. If you find yourself hardcoding pixels, you're breaking resolution independence.
- **Bounded loops.** The auto-fit loop is capped at 16 iterations so it can never spin. Keep any new measurement loops bounded too.
- **Coordinate flip happens once.** Everything after the `translateBy`/`scaleBy` assumes top-left origin. Don't draw before the flip expecting top-left coordinates.
