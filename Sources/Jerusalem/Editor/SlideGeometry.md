# `SlideGeometry.swift`

> A namespace of pure, unit-testable geometry functions (snap, clamp, alignment guides, drag/resize, layer reorder) that power the editor canvas — all in normalized 0…1 coordinates, with no UI.

**Location:** `Sources/Jerusalem/Editor/SlideGeometry.swift`
**Role:** pure geometry namespace

## What it does (plain English)

Every element on a slide is stored with a **normalized frame**: `x`, `y`, `width`, `height` are all numbers between `0` and `1` (think "fraction of the slide"), with the origin at the **top-left**. So an element at `x: 0.5, width: 0.25` starts halfway across and is a quarter of the slide wide — no matter whether the slide is rendered at 1920×1080 on a projector or 760px wide in the editor. `SlideGeometry` is the layer that does all the math on those normalized frames.

The big idea: the canvas view (`SlideCanvasView`) only ever does pixel↔normalized conversion *at the very edges* (when a finger/mouse moves N pixels, it divides by canvas size to get a normalized delta). Everything in between — "should this snap to the grid?", "is this element lined up with the slide center?", "what does dragging the top-left handle do to the frame?" — is delegated here. That keeps the hard rules in one testable place.

It's written as a **caseless `enum`** (`enum SlideGeometry { static func ... }`). In Swift, an `enum` with no cases and only `static` members is the idiomatic way to make a namespace of pure functions — the JS equivalent of `export const SlideGeometry = { ... }`. You never create an *instance* of it; you just call `SlideGeometry.clamped(...)`. Because it imports only `Foundation` (no SwiftUI/AppKit/SwiftData), it can be tested headlessly.

## Swift you'll meet in this file

- `enum SlideGeometry { ... }` — caseless enum = a pure-function namespace, like `export const SlideGeometry = {}`.
- `struct Frame { var x; var y; var width; var height }` — a value type (copied on assignment), like a plain `{x, y, width, height}` object. Its `var minX`/`maxX`/`centerX` are **computed properties** (getters), like `get minX() { return this.x }`.
- `enum Handle { case body, topLeft, top, ... }` — a closed set of named values (like a TypeScript string-union type `'body' | 'topLeft' | ...`).
- `static let defaultGridStep: Double = 0.05` — a module constant (`const`).
- `Double` = a `number`. `[Double]` = `number[]`. `[Frame]` = `Frame[]`.
- `func snapped(_ value: Double, step: Double = 0.05, enabled: Bool) -> Double` — `_` means the first argument has **no external label** (call it as `snapped(0.3, enabled: true)`); `= 0.05` is a default parameter.
- `guard enabled, step > 0 else { return value }` — early-return guard, like `if (!enabled || step <= 0) return value;`.
- `-> (line: Double, anchor: SnapAnchor)?` — returns a **named tuple**, or `nil`. A tuple is like an anonymous object `{line, anchor}`; the `?` makes the whole thing `T | null`.
- `best.map { ($0.0, $0.1) }` — `Optional.map`: run the closure only if non-nil (like `best && {...}` / optional chaining). `$0` is the first/implicit closure argument; `$0.0`/`$0.1` index into a tuple.
- `result.swapAt(i, j)`, `result.remove(at:)`, `result.insert(_, at:)` — array mutation helpers (you must copy to a `var` first, since the input is a `let`).
- `private extension Array where Element: Hashable { ... }` — adds a method (`uniqued()`) to arrays whose elements are hashable, like augmenting `Array.prototype` but type-constrained and file-private.

## Code walkthrough

### `Frame` — the normalized rectangle

```swift
struct Frame: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var minX: Double { x }
    var maxX: Double { x + width }
    var centerX: Double { x + width / 2 }
    // …minY/maxY/centerY similarly
}
```

This is the value type everything works on. The computed properties give you the "interesting" coordinates of the rectangle — its left/right/center edges — without storing them. `Equatable` lets two frames be compared with `==` (handy in tests); `Sendable` marks it safe to pass across concurrency boundaries.

### `clamped` — keep the frame grabbable

```swift
static let pasteboardMargin: Double = 0.5

static func clamped(_ frame: Frame, minSize: Double = 0.05,
                    margin: Double = pasteboardMargin) -> Frame {
    let maxSpan = 1.0 + 2 * margin
    let width = max(minSize, min(maxSpan, frame.width))
    let height = max(minSize, min(maxSpan, frame.height))
    let x = min(max(-margin, frame.x), 1.0 + margin - width)
    let y = min(max(-margin, frame.y), 1.0 + margin - height)
    return Frame(x: x, y: y, width: width, height: height)
}
```

Two jobs:

1. **Minimum size** (`minSize: 0.05`): a resize can never shrink an element below 5% — otherwise it would collapse to nothing and become impossible to grab again.
2. **Pasteboard bounds**: position is allowed to go *past* the slide edges by `margin` (0.5 = half a slide) in every direction. That's the deliberate "pasteboard" — you can drag an element half off the slide for a full-bleed design, but not infinitely far where it'd vanish. Note position is **not** pinned inside 0…1; full-bleed needs to overflow.

Example: a `Frame(x: 1.4, y: 0, width: 0.3, height: 0.3)` clamps `x` to `min(1.4, 1.0 + 0.5 - 0.3) = 1.2` — pushed back so at least part of it stays in the pasteboard region.

### `snapped` / `snappedToGrid` — magnetism to the dotted grid

```swift
static func snapped(_ value: Double, step: Double = 0.05, enabled: Bool) -> Double {
    guard enabled, step > 0 else { return value }
    return (value / step).rounded() * step
}
```

Classic snap-to-grid: divide by the step, round to the nearest integer, multiply back. With `step = 0.05`, the value `0.32` becomes `round(6.4) * 0.05 = 6 * 0.05 = 0.30`. If snapping is off, the input passes through untouched. `snappedToGrid` just applies `snapped` to all four of a frame's numbers (top-left **and** width/height), with a `max(step, ...)` floor so a snapped size never rounds down to zero.

### Alignment guides — feeling lined up with other elements

```swift
static func alignmentCandidates(against others: [Frame]) -> AlignmentCandidates {
    var verticals: [Double] = [0, 0.5, 1]
    var horizontals: [Double] = [0, 0.5, 1]
    for frame in others {
        verticals.append(contentsOf: [frame.minX, frame.centerX, frame.maxX])
        horizontals.append(contentsOf: [frame.minY, frame.centerY, frame.maxY])
    }
    return AlignmentCandidates(
        verticals: verticals.uniqued().sorted(),
        horizontals: horizontals.uniqued().sorted())
}
```

This builds the list of lines the dragged element should "feel magnetic" to: the **slide's** left/center/right (`0, 0.5, 1`) plus **every other element's** left/center/right edges. (Same for horizontals, using y values.) The result is deduped and sorted.

Then `snapVertical` checks the dragged frame's own three x-anchors (its left `minX`, its `centerX`, its right `maxX`) against those candidate lines:

```swift
static func snapVertical(frame: Frame, candidates: AlignmentCandidates,
                         tolerance: Double = 0.012) -> (line: Double, anchor: SnapAnchor)? {
    let anchors: [(Double, SnapAnchor)] = [
        (frame.minX, .leading),
        (frame.centerX, .center),
        (frame.maxX, .trailing),
    ]
    return nearest(in: candidates.verticals, anchors: anchors, tolerance: tolerance)
}
```

`nearest` (private) loops every candidate line against every anchor and returns the *closest* pair within `tolerance` (1.2% of slide width), telling you both **which line** to snap to and **which edge** of your element matched (`.leading`/`.center`/`.trailing`). `snapHorizontal` is the y-axis twin. The caller (canvas) draws a guide line at the matched line and nudges the frame so that edge lands exactly on it. A `nil` result means "nothing close enough, don't snap."

### `dragged` — what a handle does to a frame

```swift
static func dragged(_ start: Frame, by dx: Double, dy: Double, handle: Handle) -> Frame {
    switch handle {
    case .body:
        return Frame(x: start.x + dx, y: start.y + dy,
                     width: start.width, height: start.height)
    case .topLeft:
        return Frame(x: start.x + dx, y: start.y + dy,
                     width: start.width - dx, height: start.height - dy)
    case .right:
        return Frame(x: start.x, y: start.y,
                     width: start.width + dx, height: start.height)
    // …six more cases
    }
}
```

`dx`/`dy` are the drag distance **already converted to 0…1 units** by the caller. The `switch` is the heart of resize logic:

- **`.body`** moves the whole frame: add the delta to `x`/`y`, size unchanged.
- **A corner like `.topLeft`** moves *and* resizes: dragging it right (`dx > 0`) pushes `x` right and *shrinks* width by the same `dx` (so the bottom-right corner stays put).
- **An edge like `.right`** only changes one dimension: `width + dx`, position and height untouched.
- **`.top`** moves `y` down by `dy` and shrinks height by `dy` — the bottom edge is anchored.

There's no clamping or snapping here — that's layered on afterward by the caller, by piping `dragged`'s output through `snappedToGrid` and `clamped`.

### Layer reorder — `raised` / `lowered` / `movedToFront` / `movedToBack`

These operate on a plain `[Int]` (a list of element `order` values), returning a **new** reordered list:

```swift
static func raised(_ id: Int, in items: [Int]) -> [Int] {
    guard let index = items.firstIndex(of: id), index < items.count - 1 else { return items }
    var result = items
    result.swapAt(index, index + 1)
    return result
}
```

`raised` swaps an element one slot toward the end (= toward the front visually, since later = drawn on top); it no-ops if already last. `lowered` swaps the other way. `movedToFront` removes the id and appends it; `movedToBack` removes and inserts at index 0. Each guards against "not present" / "already there" and never mutates the input — it copies into a `var result`.

### `uniqued()` helper

```swift
private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
```

Order-preserving dedupe. `seen.insert($0)` returns a tuple whose `.inserted` flag is `true` only the first time a value is seen — so `filter` keeps first occurrences. Used to clean up the alignment-candidate lists.

## How it connects

`SlideGeometry` is the **engine** behind `SlideCanvasView`. During a drag, the canvas:

1. converts pixel translation → normalized `dx`/`dy`,
2. calls `SlideGeometry.dragged(...)` to get the proposed frame,
3. for body drags, asks `alignmentCandidates` + `snapVertical`/`snapHorizontal` whether to snap (and draws the guide),
4. runs the result through `snappedToGrid` then `clamped`,
5. writes the four numbers back onto the SwiftData `SlideElement`.

The layer-reorder functions back the Layers panel / arrange controls. Because none of this touches UI, the same functions are exercised directly by unit tests (the "testable core of the canvas" the project docs describe).

## Gotchas / why it matters

- **Everything is 0…1, top-left origin.** Never store pixels here. The whole point is resolution independence — a slide composed in the editor must look identical on a 4K projector.
- **`clamped` deliberately allows overflow.** Don't "fix" it to pin elements inside 0…1; the pasteboard margin is intentional for full-bleed designs, and the min-size floor is what keeps a shrunk element grabbable.
- **Order of operations matters.** `dragged` produces a raw frame; snapping and clamping are *separate* steps the caller composes. Body drags get alignment snapping; resizes only get grid snapping (see the canvas).
- **Pure and value-typed.** Functions return new `Frame`s / arrays; nothing here mutates shared state, which is exactly why it's unit-testable and safe to call mid-gesture.
