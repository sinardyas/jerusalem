# `SlideGeometry.swift`

> A namespace of pure, unit-testable geometry functions (snap, clamp, alignment guides, drag/resize, layer reorder) that power the editor canvas — all in normalized 0…1 coordinates, with no UI.

**Location:** `Sources/Jerusalem/Editor/SlideGeometry.swift`
**Role:** pure geometry namespace

## What it does (plain English)

Every element on a slide is stored with a **normalized frame**: `x`, `y`, `width`, `height` are all numbers between `0` and `1` (think "fraction of the slide"), with the origin at the **top-left**. So an element at `x: 0.5, width: 0.25` starts halfway across and is a quarter of the slide wide — no matter whether the slide is rendered at 1920×1080 on a projector or 760px wide in the editor. `SlideGeometry` is the layer that does all the math on those normalized frames.

The big idea: the canvas view (`SlideCanvasView`) only ever does pixel↔normalized conversion *at the very edges* (when a finger/mouse moves N pixels, it divides by canvas size to get a normalized delta). Everything in between — "should this snap to the grid?", "is this element lined up with the slide center?", "what does dragging the top-left handle do to the frame?" — is delegated here. That keeps the hard rules in one testable place.

It's written as a **caseless `enum`** (`enum SlideGeometry { static func ... }`). In Swift, an `enum` with no cases and only `static` members is the idiomatic way to make a namespace of pure functions — the JS equivalent of `export const SlideGeometry = { ... }`. You never create an *instance* of it; you just call `SlideGeometry.clamped(...)`. Because it imports only `Foundation` (no SwiftUI/AppKit/SwiftData), it can be tested headlessly.

## Swift you'll meet in this file

- `enum SlideGeometry { ... }` — **caseless enum** = a pure-function namespace, like `export const SlideGeometry = {}`. No instances; call `SlideGeometry.clamped(…)`.
- `struct Frame { var x; var y; var width; var height }` — a value type (copied on assignment), like a plain `{x, y, width, height}` object. Its `var minX`/`maxX`/`centerX` are **computed properties** (getters), like `get minX() { return this.x }`.
- `enum Handle { case body, topLeft, top, ... }` — **enum with cases** = a closed set of named values (like a TS string-union `'body' | 'topLeft' | …`).
- `static let defaultGridStep: Double = 0.05` — a type-level constant (`const`).
- `Double` = a `number`. `[Double]` = `number[]`. `[Frame]` = `Frame[]`.
- `func snapped(_ value: Double, step: Double = 0.05, enabled: Bool) -> Double` — `_` means the first argument has **no external label** (call it as `snapped(0.3, enabled: true)`); `= 0.05` is a default parameter.
- `guard enabled, step > 0 else { return value }` — early-return guard, like `if (!enabled || step <= 0) return value;`.
- `-> (line: Double, anchor: SnapAnchor)?` — returns a **named tuple**, or `nil`. A tuple is like an anonymous object `{line, anchor}`; the `?` makes the whole thing `T | null`.
- `switch handle { case .body: … }` — a `switch` over an enum; `.body` is leading-dot shorthand. The compiler forces every case to be handled.
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

**TypeScript equivalent**

```ts
// A normalized rectangle: x/y top-left, width/height in 0…1.
interface Frame {
  x: number;
  y: number;
  width: number;
  height: number;
}

// Swift's computed properties (minX/maxX/centerX) → plain helper functions,
// since a TS interface can't carry getters. Same arithmetic.
const FrameMath = {
  minX: (f: Frame) => f.x,
  minY: (f: Frame) => f.y,
  maxX: (f: Frame) => f.x + f.width,
  maxY: (f: Frame) => f.y + f.height,
  centerX: (f: Frame) => f.x + f.width / 2,
  centerY: (f: Frame) => f.y + f.height / 2,
};
```

**Swift syntax:**
- `struct Frame: Equatable, Sendable` — a **value type** that conforms to two protocols. `Equatable` gives `==` (the compiler synthesizes it field-by-field); `Sendable` marks it safe to hand across concurrency boundaries. TS analog: a plain object; deep-equality you'd write yourself.
- `var minX: Double { x }` — a **computed property**: a getter with no stored value (`{ x }` is shorthand for `{ return x }`). TS analog: `get minX() { return this.x }`, or a helper function.
- `var x: Double` — a stored property; because `Frame` is a `struct`, assigning a `Frame` copies it (no shared reference). TS objects are references, so treat these as immutable / clone before mutating.

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

**TypeScript equivalent**

```ts
const pasteboardMargin = 0.5;

// `_ frame` → unlabeled first arg; defaults preserved.
function clamped(
  frame: Frame,
  minSize = 0.05,
  margin = pasteboardMargin,
): Frame {
  const maxSpan = 1.0 + 2 * margin;
  const width = Math.max(minSize, Math.min(maxSpan, frame.width));
  const height = Math.max(minSize, Math.min(maxSpan, frame.height));
  const x = Math.min(Math.max(-margin, frame.x), 1.0 + margin - width);
  const y = Math.min(Math.max(-margin, frame.y), 1.0 + margin - height);
  return { x, y, width, height };
}
```

**Swift syntax:**
- `static func clamped(_ frame: Frame, minSize: Double = 0.05, …)` — `_` drops the external label on the first arg (call `clamped(f, minSize: …)`); `= 0.05` / `= pasteboardMargin` are **default parameter values**. TS analog: `function clamped(frame, minSize = 0.05, …)`.
- `max(minSize, min(maxSpan, frame.width))` — Swift's free `min`/`max` functions. TS analog: `Math.min` / `Math.max`.
- `let width = …` — `let` is an immutable binding (a `const`). TS analog: `const`.

Two jobs:

1. **Minimum size** (`minSize: 0.05`): a resize can never shrink an element below 5% — otherwise it would collapse to nothing and become impossible to grab again.
2. **Pasteboard bounds**: position is allowed to go *past* the slide edges by `margin` (0.5 = half a slide) in every direction. That's the deliberate "pasteboard" — you can drag an element half off the slide for a full-bleed design, but not infinitely far where it'd vanish. Note position is **not** pinned inside 0…1; full-bleed needs to overflow.

Example: a `Frame(x: 1.4, y: 0, width: 0.3, height: 0.3)` clamps `x` to `min(1.4, 1.0 + 0.5 - 0.3) = 1.2` — pushed back so at least part of it stays in the pasteboard region.

### `snapped` / `snappedToGrid` — magnetism to the dotted grid

```swift
static func snapped(_ value: Double, step: Double = defaultGridStep, enabled: Bool) -> Double {
    guard enabled, step > 0 else { return value }
    return (value / step).rounded() * step
}
```

**TypeScript equivalent**

```ts
const defaultGridStep = 0.05;

function snapped(value: number, enabled: boolean, step = defaultGridStep): number {
  // guard enabled, step > 0 else { return value }
  if (!enabled || step <= 0) return value;
  return Math.round(value / step) * step;
}

// snappedToGrid: apply `snapped` to all four numbers, with a floor on size.
function snappedToGrid(frame: Frame, enabled: boolean, step = defaultGridStep): Frame {
  if (!enabled) return frame;
  const x = snapped(frame.x, true, step);
  const y = snapped(frame.y, true, step);
  const w = snapped(frame.width, true, step);
  const h = snapped(frame.height, true, step);
  return { x, y, width: Math.max(step, w), height: Math.max(step, h) };
}
```

**Swift syntax:**
- `guard enabled, step > 0 else { return value }` — a **guard**: a comma-separated list of conditions that must *all* hold; if any fails, the `else` block runs (and must exit scope). TS analog: `if (!enabled || step <= 0) return value;`.
- `(value / step).rounded()` — `.rounded()` is a method on `Double` (round-half-away-from-zero by default). TS analog: `Math.round(value / step)`.

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

**TypeScript equivalent**

```ts
interface AlignmentCandidates {
  verticals: number[];
  horizontals: number[];
}

function alignmentCandidates(others: Frame[]): AlignmentCandidates {
  // slide edges + center seed the lists; var → mutable (let in TS)
  const verticals: number[] = [0, 0.5, 1];
  const horizontals: number[] = [0, 0.5, 1];
  for (const frame of others) {
    // append(contentsOf:) → push spread
    verticals.push(FrameMath.minX(frame), FrameMath.centerX(frame), FrameMath.maxX(frame));
    horizontals.push(FrameMath.minY(frame), FrameMath.centerY(frame), FrameMath.maxY(frame));
  }
  return {
    verticals: uniqued(verticals).sort((a, b) => a - b),
    horizontals: uniqued(horizontals).sort((a, b) => a - b),
  };
}
```

**Swift syntax:**
- `var verticals: [Double] = [0, 0.5, 1]` — `var` is a **mutable** binding (vs. immutable `let`); `[Double]` is `number[]`. TS analog: `let verticals: number[] = […]`.
- `for frame in others { … }` — for-in iteration. TS analog: `for (const frame of others)`.
- `verticals.append(contentsOf: […])` — appends every element of another array. TS analog: `arr.push(...other)`.
- `.uniqued().sorted()` — method chaining; `.sorted()` returns a *new* sorted array (ascending for numbers). TS analog: `arr.slice().sort((a, b) => a - b)`.

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

**TypeScript equivalent**

```ts
type SnapAnchor = "leading" | "center" | "trailing";

// Returns the matched line + which edge matched, or null (the `?` return).
function snapVertical(
  frame: Frame,
  candidates: AlignmentCandidates,
  tolerance = 0.012,
): { line: number; anchor: SnapAnchor } | null {
  // [(Double, SnapAnchor)] → an array of [number, SnapAnchor] tuples
  const anchors: [number, SnapAnchor][] = [
    [FrameMath.minX(frame), "leading"],
    [FrameMath.centerX(frame), "center"],
    [FrameMath.maxX(frame), "trailing"],
  ];
  return nearest(candidates.verticals, anchors, tolerance);
}
```

**Swift syntax:**
- `enum SnapAnchor { case leading, center, trailing }` — an **enum with cases**, a closed set of named values. TS analog: a string-union type `'leading' | 'center' | 'trailing'`.
- `-> (line: Double, anchor: SnapAnchor)?` — returns a **named tuple** (`(line:, anchor:)`) wrapped in optional (`?` = `… | null`). TS analog: `{ line: number; anchor: SnapAnchor } | null`.
- `let anchors: [(Double, SnapAnchor)]` — an array of **unlabeled tuples** `(Double, SnapAnchor)`. TS analog: `[number, SnapAnchor][]`.
- `(frame.minX, .leading)` — `.leading` is leading-dot shorthand for `SnapAnchor.leading` (type inferred). TS analog: the literal `"leading"`.

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

**TypeScript equivalent**

```ts
type Handle =
  | "body"
  | "topLeft" | "top" | "topRight"
  | "left" | "right"
  | "bottomLeft" | "bottom" | "bottomRight";

// `by dx` → external label `by`, internal name `dx`. dx/dy already in 0…1.
function dragged(start: Frame, dx: number, dy: number, handle: Handle): Frame {
  switch (handle) {
    case "body": // move only
      return { x: start.x + dx, y: start.y + dy, width: start.width, height: start.height };
    case "topLeft": // move x/y AND shrink w/h by the same delta (bottom-right anchored)
      return { x: start.x + dx, y: start.y + dy, width: start.width - dx, height: start.height - dy };
    case "top":
      return { x: start.x, y: start.y + dy, width: start.width, height: start.height - dy };
    case "topRight":
      return { x: start.x, y: start.y + dy, width: start.width + dx, height: start.height - dy };
    case "left":
      return { x: start.x + dx, y: start.y, width: start.width - dx, height: start.height };
    case "right": // grow width only
      return { x: start.x, y: start.y, width: start.width + dx, height: start.height };
    case "bottomLeft":
      return { x: start.x + dx, y: start.y, width: start.width - dx, height: start.height + dy };
    case "bottom":
      return { x: start.x, y: start.y, width: start.width, height: start.height + dy };
    case "bottomRight":
      return { x: start.x, y: start.y, width: start.width + dx, height: start.height + dy };
  }
}
```

**Swift syntax:**
- `switch handle { case .body: … case .topLeft: … }` — a `switch` over an enum; `.body` is shorthand for `Handle.body`. Swift requires **exhaustive** cases (no `default` needed if all are covered). TS analog: a `switch (handle)` — TS won't force exhaustiveness unless you add a never-check.
- `by dx: Double, dy: Double` — `by` is the external label for `dx` (so callers write `dragged(start, by: dx, dy: dy, …)`); `dx` is the name inside the body. TS analog: just `dx` (positional).

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

**TypeScript equivalent**

```ts
// `_ id, in items` → unlabeled id + external-labeled items. Returns a NEW array.
function raised(id: number, items: number[]): number[] {
  const index = items.indexOf(id);
  // guard: present AND not already last, else no-op
  if (index === -1 || index >= items.length - 1) return items;
  const result = items.slice(); // copy before mutating (Swift's `var result = items`)
  [result[index], result[index + 1]] = [result[index + 1], result[index]]; // swapAt
  return result;
}

function lowered(id: number, items: number[]): number[] {
  const index = items.indexOf(id);
  if (index <= 0) return items; // present AND not already first
  const result = items.slice();
  [result[index], result[index - 1]] = [result[index - 1], result[index]];
  return result;
}

function movedToFront(id: number, items: number[]): number[] {
  const index = items.indexOf(id);
  if (index === -1) return items;
  const result = items.slice();
  const [value] = result.splice(index, 1); // remove(at:)
  result.push(value);                       // append
  return result;
}

function movedToBack(id: number, items: number[]): number[] {
  const index = items.indexOf(id);
  if (index === -1) return items;
  const result = items.slice();
  const [value] = result.splice(index, 1);
  result.unshift(value);                    // insert(_, at: 0)
  return result;
}
```

**Swift syntax:**
- `guard let index = items.firstIndex(of: id), index < items.count - 1 else { … }` — combines **optional binding** (`firstIndex(of:)` returns `Int?`) with an extra boolean condition; both must pass. TS analog: `const index = items.indexOf(id); if (index === -1 || index >= items.length - 1) return …`.
- `var result = items` — copies the array into a *mutable* binding (the parameter `items` is an immutable `let`). Since `[Int]` is a value type, this is a real copy. TS analog: `const result = items.slice()`.
- `result.swapAt(index, index + 1)` / `.remove(at:)` / `.insert(_, at:)` — in-place array helpers. TS analog: destructuring swap / `splice` / `splice`+`unshift`.

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

**TypeScript equivalent**

```ts
// Order-preserving dedupe. A free function instead of an Array extension.
function uniqued<T>(items: T[]): T[] {
  const seen = new Set<T>();
  // filter keeps an item the FIRST time it's seen (insert reports "was it new?")
  return items.filter((x) => {
    if (seen.has(x)) return false;
    seen.add(x);
    return true;
  });
}
```

**Swift syntax:**
- `private extension Array where Element: Hashable { … }` — a **constrained extension**: adds `uniqued()` to `Array`, but only when its `Element` is `Hashable` (so it can go in a `Set`); `private` keeps it file-local. TS analog: a generic free function `uniqued<T>(items)` (you wouldn't monkey-patch `Array.prototype`).
- `return filter { seen.insert($0).inserted }` — a **trailing closure** with `$0` (the implicit first argument). `seen.insert($0)` returns a tuple whose `.inserted` flag is `true` only the first time. TS analog: `items.filter(x => …)`.

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
