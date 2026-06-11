# `SlideCanvasView.swift`

> The interactive WYSIWYG editing stage: it renders the slide, overlays selection handles + alignment guides, and translates the user's drags/resizes into normalized 0…1 mutations on the live SwiftData model.

**Location:** `Sources/Jerusalem/Editor/SlideCanvasView.swift`
**Role:** SwiftUI view

## What it does (plain English)

This is the canvas you actually drag things around on. Visually it's a **stack of layers** (a `ZStack`): at the bottom, the slide rendered by the shared renderer; on top of that, an optional dashed "safe area" outline; on top of *that*, one invisible interaction overlay per element (the click target, selection outline, and 8 resize handles); and finally the blue alignment guide lines when something snaps.

The interesting part is the **coordinate conversion**. The model stores everything in normalized 0…1 (fraction of the slide). The screen, however, has a real pixel size that depends on zoom and window size. A `GeometryReader` measures the canvas's on-screen size (`canvasSize`), and the view multiplies normalized values by that to get pixels for *display*, and divides pixel drag distances by it to get normalized deltas for *editing*. That single multiply/divide at the boundary is the entire bridge between "stored as fractions" and "drawn in pixels."

Crucially, the canvas edits the **live `@Model` directly** — it's a `@Bindable var slide` and it writes `element.x = ...` straight onto the model. That's safe because the audience output works off a separate value-type *snapshot* held in `LiveState`, which doesn't change until the operator acts. But the slide grid thumbnail and the inspector preview, which read the same model through the shared renderer, update live as you drag. Every finished gesture sets `slide.isManuallyEdited = true` so the `ContentRebuilder` knows to leave this hand-edited slide alone.

## Swift you'll meet in this file

- `struct SlideCanvasView: View { var body: some View }` — a SwiftUI view ≈ a React function component; `body` ≈ returned JSX; `some View` = opaque return type.
- `@Bindable var slide: Slide` — make two-way bindings from a SwiftData `@Model`; writing `slide.x = …` mutates the live model. `@Binding var selection` — a two-way prop passed from the parent (like `[value, setValue]`).
- `var snapToGrid: Bool`, `var aspectRatio: CGFloat = 16/9` — plain props with defaults.
- `var onDuplicate: ((SlideElement) -> Void)? = nil` — an **optional callback prop**; `?` makes it nullable, called as `onDuplicate?(element)` (optional chaining — only fires if the parent passed one).
- `@State private var dragOrigin: ...? = nil` — `useState` for transient drag bookkeeping.
- `GeometryReader { geometry in … geometry.size }` — a view that hands you its measured size, like a `ResizeObserver`/measuring container. **This is the pixel↔normalized bridge.**
- `ZStack` = layered stack (z-order); `ForEach(elements) { element in … }` = `.map` over a list to views.
- `CGSize` = `{width, height}`; `CGRect` = `{x, y, width, height}` with computed `midX`/`maxY` etc.; `CGPoint` = `{x, y}`.
- `.gesture(DragGesture(minimumDistance: 1).onChanged { value in … }.onEnded { … })` = pointer drag handler; `value.translation` is the cumulative drag offset.
- `.onTapGesture { }` / `.onTapGesture(count: 2) { }` = click / double-click; `.contextMenu { }` = right-click menu.
- `.allowsHitTesting(false)` = `pointer-events: none` (purely decorative layer). `.contentShape(Rectangle())` = make the whole rect clickable even where it's transparent.
- `@ViewBuilder private func elementOverlay(...) -> some View` — a function that returns view content (lets you use `if`/`ForEach` inside).
- `static let handles: [HandleDescriptor]` / `static func handleView(...)` — type-level constants/helpers (shared, not per-instance).
- `element.persistentModelID` — SwiftData's stable identity for a model row (used as the selection key).

## Code walkthrough

### `body` — the layered stage

```swift
var body: some View {
    GeometryReader { geometry in
        let canvasSize = geometry.size
        ZStack {
            // 1. Base slide via the shared renderer.
            RenderableSlideView(renderable: RenderableSlide(slide), aspectRatio: aspectRatio)
                .contentShape(Rectangle())
                .onTapGesture { selection = nil }   // click empty space → deselect
            // 2. Safe-area dashed inset (5%), toggleable, non-interactive.
            if showSafeArea { … .padding(canvasSize.width * 0.05) … }
            // 3. One interaction overlay per element, in render order.
            ForEach(elements) { element in
                elementOverlay(element, canvasSize: canvasSize)
            }
            // 4. Alignment guide lines (drawn only while snapped).
            if showGuides, let x = activeVerticalGuide { … .position(x: x * canvasSize.width, …) }
            if showGuides, let y = activeHorizontalGuide { … .position(y: y * canvasSize.height) }
        }
    }
    .aspectRatio(aspectRatio, contentMode: .fit)
}
```

`GeometryReader` is the load-bearing wrapper: `canvasSize` is the live pixel size of the stage. Notice how guides are positioned — `x * canvasSize.width`. The guide's `x` is normalized (e.g. `0.5` = center), and multiplying by `canvasSize.width` turns it into a pixel x. That multiply pattern repeats everywhere a normalized value needs to be drawn.

`RenderableSlide(slide)` snapshots the model into the immutable value type the shared renderer wants — the canvas draws the slide through the exact same path as the projector, so what you edit is what the audience gets.

### `elementOverlay` — hit target + outline + 8 handles

```swift
let frame = SlideGeometry.Frame(
    x: element.x, y: element.y, width: element.width, height: element.height)
let rect = CGRect(
    x: frame.x * canvasSize.width,  y: frame.y * canvasSize.height,
    width: frame.width * canvasSize.width, height: frame.height * canvasSize.height)
```

Here's the conversion in one place: take the element's normalized frame and multiply each component by the matching canvas dimension to get a **pixel `CGRect`**. Everything below is drawn relative to `rect`.

```swift
Color.clear
    .contentShape(Rectangle())
    .frame(width: rect.width, height: rect.height)
    .position(x: rect.midX, y: rect.midY)
    .gesture(dragGesture(for: element, handle: .body, canvasSize: canvasSize))
    .onTapGesture(count: 2) { if element.kind == .text { onInlineEditRequest?(element) } }
    .onTapGesture { selection = element.persistentModelID }
    .contextMenu {
        Button("Duplicate") { onDuplicate?(element) }
        Button("Delete", role: .destructive) { onDelete?(element) }
    }
```

An invisible (`Color.clear`) rectangle the exact size of the element is the **body hit target**: single-click selects it, double-click on a text element asks the parent to open the inline text editor, right-click offers Duplicate/Delete, and a drag on it moves the whole element (`handle: .body`).

When the element *is* selected, the overlay adds the accent outline and the eight handles:

```swift
if isSelected {
    Rectangle().strokeBorder(Color.accentColor, lineWidth: 1.5)
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
    ForEach(Self.handles, id: \.position) { handle in
        Self.handleView(handle: handle.kind, in: rect)
            .gesture(dragGesture(for: element, handle: handle.kind, canvasSize: canvasSize))
    }
}
```

The 8 handles are described once in a static table (`tl, tm, tr, ml, mr, bl, bm, br` mapped to `SlideGeometry.Handle` cases). `handlePoint` computes each one's pixel position from `rect`'s edges (`minX/midX/maxX` × `minY/midY/maxY`), and `handleView` draws an 11pt white square with an accent stroke at that point. Each handle gets the **same `dragGesture`** but with its own `handle:` value — so the gesture math (via `SlideGeometry.dragged`) knows whether you're moving the body or pulling a specific corner/edge.

### `dragGesture` — the heart of drag/resize

```swift
DragGesture(minimumDistance: 1)
    .onChanged { value in
        if dragOrigin == nil {                       // first frame of the gesture
            selection = element.persistentModelID
            dragOrigin = SlideGeometry.Frame(x: element.x, y: element.y,
                                             width: element.width, height: element.height)
            dragHandle = handle
        }
        guard let origin = dragOrigin, let activeHandle = dragHandle else { return }
        let dx = value.translation.width / canvasSize.width    // ← pixels → normalized
        let dy = value.translation.height / canvasSize.height
        var next = SlideGeometry.dragged(origin, by: dx, dy: dy, handle: activeHandle)
        …
        element.x = next.x; element.y = next.y
        element.width = next.width; element.height = next.height
    }
    .onEnded { _ in
        dragOrigin = nil; dragHandle = nil
        activeVerticalGuide = nil; activeHorizontalGuide = nil
        slide.isManuallyEdited = true
    }
```

The flow each gesture-frame:

1. **On the first frame**, capture an immutable `dragOrigin` (the frame as it was when the drag started) so all math is relative to the start, not accumulated drift. SwiftUI's `value.translation` is already cumulative-from-start, which is why an immutable origin is correct.
2. **Convert** the pixel translation to normalized by dividing by `canvasSize` — the inverse of the multiply used for display.
3. **Apply the handle math**: `SlideGeometry.dragged(origin, by: dx, dy: dy, handle:)` returns the proposed frame (body = move; corner/edge = resize).
4. **Snap** (next section).
5. **Write back** the four numbers onto the live model. Because it's a `@Model`, this is immediately observed by the renderer, so the thumbnail and preview move in real time.

`onEnded` clears the transient drag/guide state and flips `isManuallyEdited`.

### Snapping inside the gesture

```swift
if activeHandle == .body {
    let candidates = SlideGeometry.alignmentCandidates(
        against: elements
            .filter { $0.persistentModelID != element.persistentModelID }
            .map(Self.frame(of:)))
    if let v = SlideGeometry.snapVertical(frame: next, candidates: candidates) {
        next = adjusted(next, snappingVerticalAnchor: v.anchor, to: v.line)
        activeVerticalGuide = v.line
        toastCenter?.show(toastLabel(forVerticalLine: v.line, anchor: v.anchor))
    } else { activeVerticalGuide = nil }
    // …same for horizontal…
}
next = SlideGeometry.snappedToGrid(next, enabled: snapToGrid)
next = SlideGeometry.clamped(next)
```

Two kinds of snapping, in a deliberate order:

- **Alignment snapping** only happens for **body** drags. It builds candidate lines from *the other* elements (filtering out the one being dragged) plus the slide edges/center, asks `SlideGeometry` if any of the dragged frame's edges are within tolerance, and if so nudges the frame onto that line (`adjusted(...)`), lights up the blue guide (`activeVerticalGuide`), and shows a toast ("Snapped to center / edge / element"). Resizes skip this.
- **Grid snapping + clamping** apply to *everything*, last: coast onto the 5% grid (if enabled), then clamp to min-size + pasteboard bounds.

`adjusted` translates a snap result back into a corrected frame depending on which edge matched:

```swift
switch anchor {
case .leading:  f.x = line                 // left edge sits on the line
case .center:   f.x = line - f.width / 2   // center sits on the line
case .trailing: f.x = line - f.width        // right edge sits on the line
}
```

(The horizontal twin does the same with `y`/`height`.)

## How it connects

- **Parent (`SlideEditorView`)** owns the `slide`, the `selection` binding, the toggles (`snapToGrid`/`showSafeArea`/`showGuides`), and the callbacks. It hands them in and reacts: `onInlineEditRequest` floats a text editor, `onDuplicate`/`onDelete` mutate the model, and `selection` flows to the inspector so the right properties show.
- **`SlideGeometry`** does all the actual math — `dragged`, `alignmentCandidates`, `snapVertical/Horizontal`, `snappedToGrid`, `clamped`, plus the `Frame`/`Handle`/`SnapAnchor` types. The canvas is mostly glue: convert coordinates, call geometry, write the model.
- **The shared renderer** (`RenderableSlideView` + `RenderableSlide`) draws the base slide — the same code path used by the audience output and the grid thumbnails.
- **Undo** comes for free: the parent installs an `UndoManager` on the `modelContext`, and every `element.x = …` write the gesture makes is tracked, so ⌘Z reverts drags.

## Gotchas / why it matters

- **Multiply to draw, divide to edit.** Normalized × `canvasSize` = pixels (display); pixel translation ÷ `canvasSize` = normalized (editing). If you ever see a coordinate not paired with `canvasSize`, suspect a bug.
- **`GeometryReader` is mandatory.** Without the measured `canvasSize`, there's no way to convert — that's why the whole body lives inside it.
- **Capture `dragOrigin` once.** Re-reading `element.x` mid-drag would compound the already-cumulative `value.translation` and the element would accelerate away. The immutable origin is the fix.
- **Editing the live model is intentional, not a leak.** The audience screen is protected by `LiveState`'s value snapshot; only the editor's own previews/thumbnails update live. Don't "fix" this by snapshotting the editor.
- **`isManuallyEdited` on every `onEnded`.** This is what tells `ContentRebuilder` to stop regenerating this slide from the song/Bible source — forget it and a hand-positioned element gets wiped on the next content edit.
- **Body vs. handle decides snapping.** Only body drags get the magnetic alignment guides; resizes only hit the grid. That's a UX choice baked into the gesture, not the geometry.
