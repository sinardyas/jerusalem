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
| `enum SlideRenderer { static func ... }` | A **caseless enum** used as a namespace of static functions — no instances exist. Shape ≈ `export const SlideRenderer = { ... }` |
| `static let referenceHeight: CGFloat = 1080` | A type-level constant: `static readonly referenceHeight = 1080`; `CGFloat` is just a graphics `number` |
| `CGContext` | A drawing canvas (Core Graphics) — issue paint commands to it, like an HTML `CanvasRenderingContext2D` |
| `CGImage` | The finished bitmap produced from the canvas |
| `NSColor`, `NSImage`, `NSBezierPath`, `NSFont` | AppKit types: a color, an image, a vector path, a font |
| `NSAttributedString` | Styled text — a string plus per-range attributes (font, color, shadow…) |
| `guard let context = ... else { return nil }` | Early-exit bind: if construction fails, return `null` immediately; otherwise `context` is non-null below |
| `switch slide.backgroundKind { case .video: ... }` | A `switch` over an enum; the compiler requires it to be **exhaustive** |
| `defer { ... }` | Run this block when the function exits, however it exits (like `try { } finally { }`) |
| `context.translateBy / scaleBy` | Transform the canvas coordinate system (move/flip) — like `ctx.translate()` / `ctx.scale()` |
| `0..<16` | A half-open range `0,1,…,15` — like `for (let i = 0; i < 16; i++)` |
| `?? .black` | Nullish coalescing — fall back to `.black` if the hex parse returns `null` |
| `[.usesLineFragmentOrigin, .usesFontLeading]` | An **option set** — a bit-flag set written as an array literal, ≈ passing `{ usesLineFragmentOrigin: true, ... }` flags |
| `attributes[.kern] = value` | Subscript-assign into a dictionary keyed by an attribute enum, ≈ `attributes.set(Key.kern, value)` |

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

**TypeScript equivalent**

```ts
// analogy: makeImage is the one exported drawing function on the namespace.
export const SlideRenderer = {
  makeImage(slide: RenderableSlide, pixelSize: CGSize): CGImage | null {
    const width = Math.max(1, Math.round(pixelSize.width));
    const height = Math.max(1, Math.round(pixelSize.height));

    // analogy: const ctx = offscreenCanvas(width, height).getContext("2d");
    const context = makeRGBAContext(width, height); // CGContext, RGBA, 8bpc
    if (context == null) return null;               // guard ... else return nil
    // ...
  },
};
```

It clamps the size to at least 1×1 and creates an RGBA off-screen bitmap canvas. If the OS can't make the canvas, it returns `nil` rather than crashing.

**Swift syntax:**
- `enum SlideRenderer { static func ... }` — a **caseless `enum`**: it has no cases and can't be instantiated, so it's purely a namespace bag of `static` functions. The idiomatic TS analog is a frozen object `export const SlideRenderer = { makeImage(...) { ... } }`.
- `static func makeImage(_ slide:..., pixelSize:)` — `static` = called on the type, not an instance (`SlideRenderer.makeImage(...)`). `_ slide` is positional; `pixelSize:` keeps its label at the call site.
- `guard let context = ... else { return nil }` — bind-or-bail: if the right-hand side is `nil`, run `else` (which must exit); otherwise `context` is the unwrapped, non-optional value for the rest of the function.

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

**TypeScript equivalent**

```ts
switch (slide.backgroundKind) {
  case "video":
    break; // leave transparent — the live <video> composites behind
  case "image":
    // analogy: ctx.fillStyle = "#000"; ctx.fillRect(0, 0, w, h);
    context.setFillColor(black);
    context.fill({ x: 0, y: 0, width: size.width, height: size.height });
    break;
  case "color": {
    const base = NSColor.fromHex(slide.backgroundColorHex) ?? black; // ?? .black
    context.setFillColor(base);
    context.fill({ x: 0, y: 0, width: size.width, height: size.height });
    break;
  }
  case "gradient":
    drawGradient(slide, context, size);
    break;
}
```

For a video background it paints nothing (transparent) so the actual looping video shows through. For an image background it paints black first so any letterboxing around an off-aspect photo looks intentional ("theatre, not bleed").

**Swift syntax:**
- `switch` over an enum is **exhaustive** — every case must be handled (or a `default`), so the compiler catches you if a new background kind is added. Each `case` does *not* fall through (no `break` needed to stop); `break` here means "do nothing for this case."
- `?? .black` — nullish coalescing: `NSColor(hex:)` returns `NSColor?`; if `nil`, use `.black`. (`.black` is leading-dot shorthand for `NSColor.black`, since the type is inferred.)

**Coordinate flip.** Core Graphics is bottom-left origin; the slide model is top-left. So it flips the canvas vertically once, then all drawing matches the normalized top-left coordinates:

```swift
context.translateBy(x: 0, y: size.height)
context.scaleBy(x: 1, y: -1)
```

**TypeScript equivalent**

```ts
// analogy: move the origin down then flip Y so (0,0) is top-left.
context.translate(0, size.height); // ctx.translate(0, h)
context.scale(1, -1);              // ctx.scale(1, -1)
```

It then activates an `NSGraphicsContext` (so AppKit text/image APIs draw into this canvas) and uses `defer` to restore the graphics state on the way out — guaranteed cleanup.

**Swift syntax:**
- `defer { ... }` — schedules cleanup to run when the current scope exits, no matter the exit path (early return, throw, fallthrough). Mentally it's the `finally` of a `try/finally` placed right next to the setup it pairs with.

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

**TypeScript equivalent**

```ts
const scale = size.height / SlideRenderer.referenceHeight;
for (const element of slide.elements) {
  switch (element.kind) {
    case "shape": drawShapeElement(element, size, scale); break;
    case "image": drawImageElement(element, size); break;
    case "text":  draw(element, size, scale); break;
  }
}
return context.makeImage();
```

`scale` is the bridge from the 1080-reference to the real output — every font size and corner radius gets multiplied by it. The comment notes there's no fixed shape→image→text layering; the Layers panel controls stacking via element order.

**Swift syntax:**
- `for element in slide.elements` — the standard for-of loop; `slide.elements` is an array.

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

**TypeScript equivalent**

```ts
fittedFontSize(/* text, fontName, isBold, isItalic, baseSize, boxSize */): number {
  const minSize = Math.max(8, baseSize * 0.25);
  let fontSize = baseSize;
  for (let i = 0; i < 16; i++) {                 // 0..<16, bounded loop
    const attributed = measuringString(/* ... */);
    // analogy: measure wrapped text height at this font size (ctx.measureText-ish)
    const fitted = boundingRect(attributed, boxSize.width, Infinity);
    if (fitted.height <= boxSize.height || fontSize <= minSize) break;
    const ratio = boxSize.height / fitted.height;
    // shrink by a damped ratio: never below 0.6x or above 0.95x per step
    fontSize = Math.max(minSize, fontSize * Math.min(0.95, Math.max(0.6, ratio)));
  }
  return fontSize;
}
```

It measures the wrapped text height, and if it's too tall, multiplies the font down by a damped ratio (never less than 0.6× or more than 0.95× per step, clamped to a floor of 8pt or 25% of the base). It iterates at most 16 times — a bounded loop, so it can never hang. This is `static` and documented as "exposed for testing the auto-fit rule," so the math is unit-tested directly.

**Swift syntax:**
- `var fontSize = baseSize` — `var` is a mutable local (reassigned in the loop); a `let` here would be a `const` and couldn't be reassigned.
- `for _ in 0..<16` — `0..<16` is a **half-open range** (0 through 15). The `_` discards the loop index — we only want to iterate a bounded number of times.
- `[.usesLineFragmentOrigin, .usesFontLeading]` — an **OptionSet** literal: a set of bit flags written like an array. Conceptually `{ usesLineFragmentOrigin: true, usesFontLeading: true }` passed as one value.

### Background drawing helpers

`drawGradient` builds a two-stop linear gradient and computes start/end points from `gradientAngle` so the gradient runs corner-to-corner at any angle; if a color is missing it falls back to a solid fill. `aspectFill` computes the rect to scale an image so it *covers* a box while keeping aspect ratio (cropping overflow).

```swift
private static func drawGradient(slide: RenderableSlide,
                                 in context: CGContext, size: CGSize) {
    let start = NSColor(hex: slide.backgroundColorHex) ?? .black
    let end = NSColor(hex: slide.gradientHex2 ?? slide.backgroundColorHex) ?? start
    ...
    let radians = slide.gradientAngle * .pi / 180
    let dx = cos(radians), dy = sin(radians)
    let half = CGPoint(x: size.width / 2, y: size.height / 2)
    let extent = abs(dx) * (size.width / 2) + abs(dy) * (size.height / 2)
    let startPoint = CGPoint(x: half.x - dx * extent, y: half.y - dy * extent)
    let endPoint = CGPoint(x: half.x + dx * extent, y: half.y + dy * extent)
    context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
}
```

**TypeScript equivalent**

```ts
function drawGradient(slide: RenderableSlide, context: CGContext, size: CGSize): void {
  const start = NSColor.fromHex(slide.backgroundColorHex) ?? black;
  const end = NSColor.fromHex(slide.gradientHex2 ?? slide.backgroundColorHex) ?? start;
  // ... if the gradient can't be built, fall back to a solid fill of `start`.

  const radians = (slide.gradientAngle * Math.PI) / 180;
  const dx = Math.cos(radians), dy = Math.sin(radians);
  const half = { x: size.width / 2, y: size.height / 2 };
  // project the half-diagonal onto the direction vector → corner-to-corner fill
  const extent = Math.abs(dx) * (size.width / 2) + Math.abs(dy) * (size.height / 2);
  const startPoint = { x: half.x - dx * extent, y: half.y - dy * extent };
  const endPoint   = { x: half.x + dx * extent, y: half.y + dy * extent };
  // analogy: const g = ctx.createLinearGradient(sx, sy, ex, ey);
  context.drawLinearGradient(gradient, startPoint, endPoint);
}
```

**Swift syntax:**
- `private static func` — `private` scopes it to this file/type; `static` keeps it on the namespace, not an instance.
- `slide.gradientHex2 ?? slide.backgroundColorHex` — `??` again: if the optional second stop is `nil`, reuse the base color, so a one-color gradient degrades to a solid.

### Element drawing

`drawImageElement` loads a per-element image and aspect-fills it into the element's normalized box — and crucially, a missing or unloadable file is a **silent no-op**:

```swift
guard let image = NSImage(contentsOf: url) else { return }
```

**TypeScript equivalent**

```ts
const image = loadImage(url);          // NSImage(contentsOf:) -> Image | null
if (image == null) return;             // silent no-op: a deleted clip can't crash
```

A deleted clip can't crash the renderer mid-service; the slide's other elements still draw.

`drawShapeElement` builds a rectangle / ellipse / rounded-rectangle path, fills it (defaulting to system blue if the hex is bad), and optionally strokes a border whose width scales like the font does. The corner radius is clamped so it can't exceed half the smaller side.

```swift
let path: NSBezierPath
switch element.shapeType {
case .rectangle:
    path = NSBezierPath(rect: box)
case .ellipse:
    path = NSBezierPath(ovalIn: box)
case .roundedRectangle:
    let radius = min(element.cornerRadius * scale, min(box.width, box.height) / 2)
    path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
}

NSGraphicsContext.saveGraphicsState()
(NSColor(hex: element.fillColorHex) ?? .systemBlue).setFill()
path.fill()
if element.hasStroke {
    (NSColor(hex: element.strokeColorHex) ?? .black).setStroke()
    path.lineWidth = max(0.1, element.strokeWidth) * scale
    path.stroke()
}
NSGraphicsContext.restoreGraphicsState()
```

**TypeScript equivalent**

```ts
// analogy: build a Path2D, then fill/stroke it on the canvas context.
let path: Path2D;
switch (element.shapeType) {
  case "rectangle":
    path = rectPath(box); break;
  case "ellipse":
    path = ovalPath(box); break;
  case "roundedRectangle": {
    // clamp radius so it can't exceed half the smaller side
    const radius = Math.min(element.cornerRadius * scale, Math.min(box.width, box.height) / 2);
    path = roundedRectPath(box, radius);
    break;
  }
}

saveState();                                              // saveGraphicsState
setFillColor(NSColor.fromHex(element.fillColorHex) ?? systemBlue);
fill(path);                                               // ctx.fill(path)
if (element.hasStroke) {
  setStrokeColor(NSColor.fromHex(element.strokeColorHex) ?? black);
  setLineWidth(Math.max(0.1, element.strokeWidth) * scale);
  stroke(path);                                           // ctx.stroke(path)
}
restoreState();                                           // restoreGraphicsState
```

### Text drawing

`draw` computes the box, applies auto-fit if enabled, builds the styled string, then vertically centers the text block in its box before drawing:

```swift
let drawRect = CGRect(x: box.minX, y: box.minY + (box.height - textHeight) / 2,
                      width: box.width, height: textHeight)
attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin], context: nil)
```

**TypeScript equivalent**

```ts
// vertically center the measured text block inside the element box
const drawRect = {
  x: box.minX,
  y: box.minY + (box.height - textHeight) / 2,
  width: box.width,
  height: textHeight,
};
// analogy: ctx.fillText / a layout engine drawing wrapped, styled text into drawRect
attributed.draw(drawRect, { usesLineFragmentOrigin: true });
```

`font(...)` is the careful part — the picker offers *family* names (like "Avenir Next"), but `NSFont(name:)` only accepts PostScript names. So it resolves the family through an `NSFontDescriptor` and applies bold/italic as symbolic traits, with layered fallbacks (drop the trait, then fall back to the system font) so an unknown family never produces blank text.

```swift
var traits: NSFontDescriptor.SymbolicTraits = []
if isBold { traits.insert(.bold) }
if isItalic { traits.insert(.italic) }
let base = NSFontDescriptor(fontAttributes: [.family: name])
let descriptor = traits.isEmpty ? base : base.withSymbolicTraits(traits)
if let resolved = NSFont(descriptor: descriptor, size: size) { return resolved }
if let plain = NSFont(descriptor: base, size: size) { return plain }
var system = NSFont.systemFont(ofSize: size)
...
return system
```

**TypeScript equivalent**

```ts
// analogy: resolve a CSS-ish font from a family name + bold/italic flags,
// with fallbacks so an unknown family never yields blank text.
const traits = new Set<FontTrait>();        // OptionSet -> a Set of flags
if (isBold) traits.add("bold");
if (isItalic) traits.add("italic");

const base = fontDescriptor({ family: name });
const descriptor = traits.size === 0 ? base : withTraits(base, traits);

const resolved = makeFont(descriptor, size);
if (resolved != null) return resolved;       // if let resolved = ...
const plain = makeFont(base, size);          // family lacks the trait
if (plain != null) return plain;

let system = systemFont(size);               // unknown family fallback
// ...apply traits to the system font if possible...
return system;
```

**Swift syntax:**
- `var traits: ... = []` — an empty **OptionSet**; `.insert(.bold)` adds a flag, `traits.isEmpty` tests it. Think `Set<Flag>` with `.add()`.
- `traits.isEmpty ? base : base.withSymbolicTraits(traits)` — the ternary, same as JS `cond ? a : b`.
- `if let resolved = NSFont(...) { return resolved }` — optional binding as a guard-and-return ladder: try each fallback, return the first that succeeds.

`styledString` assembles all the `NSAttributedString` attributes — color, paragraph style (alignment + line spacing), optional letter spacing (`.kern`, scaled for auto-fit), underline, stroke (a negative `.strokeWidth` means "fill *and* stroke"), and a drop shadow with scaled offset/blur. Line spacing math is subtle:

```swift
style.lineSpacing = max(0, fontSize * (lineSpacingMultiplier - 1.0))
```

**TypeScript equivalent**

```ts
// AppKit lineSpacing is *additional* leading, so subtract 1 from the multiplier:
// a 1.0 multiplier => zero extra spacing.
style.lineSpacing = Math.max(0, fontSize * (lineSpacingMultiplier - 1.0));
```

AppKit's `lineSpacing` is *additional* leading, so it subtracts 1 from the multiplier before scaling — a 1.0 multiplier means zero extra spacing.

The attribute dictionary is built up incrementally, keyed by attribute name:

```swift
var attributes: [NSAttributedString.Key: Any] = [
    .font: font(element.fontName, size: fontSize, isBold: element.isBold, isItalic: element.isItalic),
    .foregroundColor: NSColor(hex: element.colorHex) ?? .white,
    .paragraphStyle: paragraph(element.alignment, fontSize: fontSize, ...),
]
if element.letterSpacing != 0 {
    attributes[.kern] = element.letterSpacing * scale
}
if element.isUnderlined {
    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
}
```

**TypeScript equivalent**

```ts
// a styled-text attribute bag keyed by attribute name (≈ a CSS style object)
const attributes = new Map<TextAttributeKey, unknown>([
  ["font", makeFont(element.fontName, fontSize, element.isBold, element.isItalic)],
  ["foregroundColor", NSColor.fromHex(element.colorHex) ?? white],
  ["paragraphStyle", paragraph(element.alignment, fontSize /* , lineSpacing */)],
]);
if (element.letterSpacing !== 0) {
  attributes.set("kern", element.letterSpacing * scale); // scaled for autofit
}
if (element.isUnderlined) {
  attributes.set("underlineStyle", UnderlineStyle.single);
}
```

**Swift syntax:**
- `[NSAttributedString.Key: Any]` — a heterogeneous dictionary (values of any type), like `Map<Key, unknown>`; built with a dictionary literal then mutated via subscript-assign `attributes[.kern] = ...`.
- `.kern`, `.underlineStyle`, `.single` — leading-dot shorthand for enum/static members where the type is inferred from context (`NSAttributedString.Key.kern`, etc.).

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
