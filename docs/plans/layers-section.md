# Layers Section — Reorder & Delete Objects in the Slide Editor

## Context

The slide editor lets users add text / image / shape objects to a slide but offers no visual way to
see and restack them — z-order is only nudgeable via the Arrange section's Front/Forward/Back
buttons, and (previously) the renderer **always drew text on top of images/shapes**, so cross-type
reordering had no visible effect. This change adds a **Layers** panel: a draggable list of the current
slide's objects to reorder their stacking, plus an easy delete. Decision (with the user): **true free
layering** — any object can be moved above or below any other, including text.

Outcome: a "Layers" section in the editor inspector showing every object on the slide (front at top),
drag-to-reorder, click-to-select (synced with the canvas), and delete via a per-row trash button **and**
the Delete key — backed by a renderer that draws strictly by layer order.

## Approach

### 1. Renderer: single ordered pass (the behavioral enabler)
`Sources/Jerusalem/Rendering/SlideRenderer.swift` — replace the three-pass loop (shape → image →
text) with **one pass in `order`**:
```swift
for element in slide.elements {            // already order-sorted (back→front)
    switch element.kind {
    case .shape: drawShapeElement(element, in: size, scale: scale)
    case .image: drawImageElement(element, in: size)
    case .text:  draw(element, in: size, scale: scale)
    }
}
```
`RenderableSlide.elements` is built from `slide.orderedElements` (ascending `order`), and the three
draw helpers are stateless/kind-independent, so this is a minimal, safe swap. Removes the implicit
"text always on top" backstop (now user-controlled via layers). New objects still add on top
(`nextOrder` = max+1) — unchanged — so the common case (derived slides = single text element) renders
identically. This same path feeds the canvas, thumbnails, Show preview, and live output, so layering
is consistent everywhere.

### 2. New `SlideLayersSection` (Editor/SlideLayersSection.swift)
An `InspectorSection(title: "Layers")` containing a `List` of the slide's objects, **front at top**
(`slide.orderedElements.reversed()`):
- `List(selection: $selection)` — clicking a row sets the editor's `selection` (highlights the object
  on the canvas), mirroring `SlideNavigatorView`'s `List(selection:)` pattern. Tags are
  `element.persistentModelID as PersistentIdentifier?`.
- Each row (`LayerRow`): a small kind glyph + color (mirroring `InspectorHeaderChip`'s descriptor:
  text→`textformat`/orange, image→`photo`/blue, shape→`square.on.circle`/purple), the object's
  `layerName`, a `Spacer`, and a trailing **trash button** (`onDelete(element)`).
- `.onMove(perform:)` for **drag reorder** (first drag-reorder list in the app) → calls the pure
  `SlideLayers.reorder` helper, then `onChange()`.
- `.onDeleteCommand { … }` deletes the selected object via the `onDelete` callback (fires only when the
  list is focused — no clash with inspector text fields, which is why a bare `⌘⌫` was avoided before).
- Bounded height (e.g. `min(count, 6) * rowHeight`) with `.scrollDisabled` when items fit, so the List
  nests cleanly inside the inspector `ScrollView`. Empty state: "No objects on this slide yet."

### 3. Pure reorder helper (testable) — `SlideLayers` enum (in SlideLayersSection.swift)
Mirrors `SlideArrangeSection.reorder`'s "rewrite `order` from positions" pattern, for a front-first
drag:
```swift
enum SlideLayers {
    /// Applies a front-first layer-list move and rewrites `order` (back-most = 0 … front-most = n-1).
    static func reorder(frontFirst elements: [SlideElement], from source: IndexSet, to destination: Int) {
        var arr = elements
        arr.move(fromOffsets: source, toOffset: destination)
        let count = arr.count
        for (i, element) in arr.enumerated() { element.order = count - 1 - i }
    }
}
```

### 4. Wire selection + delete through the inspector
- `Editor/SlideInspectorView.swift`: add `@Binding var selection: PersistentIdentifier?` and
  `var onDelete: (SlideElement) -> Void`; insert `SlideLayersSection(slide: slide, selection: $selection,
  onDelete: onDelete, onChange: markEdited)` **after** `SlideBackgroundSection`, before the conditional
  `SlideArrangeSection`. (Keep the Arrange Front/Forward/Back buttons — complementary.)
- `Editor/SlideEditorView.swift`: at the single call site, pass `selection: $selection, onDelete: delete`
  (the existing `delete(_:)` already clears selection/inline-edit and marks edited).

### 5. `SlideElement.layerName` (Models/SlideElement.swift)
A small computed label for rows: text → trimmed snippet (≤32 chars) or "Text"; image →
`imageFilename` or "Image"; shape → "Rectangle"/"Ellipse"/"Rounded Rectangle".

## Reuse
- Order-rewriting pattern from `SlideArrangeSection.reorder` (`Editor/SlideArrangeSection.swift`).
- `InspectorSection`/`InspectorRow` + the kind→glyph descriptor from `InspectorHeaderChip`
  (`Editor/InspectorSection.swift`).
- `List(selection:)` + `.tag` pattern from `SlideNavigatorView`.
- `SlideEditorView.delete(_:)` for deletion; the editor's `selection` state for canvas sync.
- `slide.orderedElements` (`Models/Slide.swift`); the stateless draw helpers in `SlideRenderer`.

## Risks
- **Legibility backstop removed**: adding an image/shape to a text slide now lands it *on top* of the
  text (it gets max+1 order); the user drags it below in the Layers panel. This is the accepted
  trade-off of free layering and is standard design-tool behavior. No auto-generated slide is affected
  (single text element).
- **List inside ScrollView**: bound the List height + `scrollDisabled` when small to avoid nested-scroll
  jank.
- **Drag on macOS**: `.onMove` row-drag works without an explicit edit mode on macOS Lists; verify the
  drag feels right on hardware.

## Verification
- `xcodebuild -scheme Jerusalem -destination 'platform=macOS' build` and
  `xcodebuild test … ` — all 84 existing tests must still pass (renderer change is order-only; no
  existing test mixes element kinds).
- **New tests** (`Tests/JerusalemTests`):
  - `SlideLayers.reorder` rewrites `order` correctly for a few moves (3 elements, move front↔back).
  - Renderer single-pass ordering: two full-slide shapes — the higher-`order` one wins the center pixel;
    swap orders → the other wins (proves cross-element stacking honors `order`).
  - `SlideElement.layerName` for text/image/shape.
- **Run the app**: open the editor, add a text + a shape + an image; the Layers section lists all three
  (front at top); drag to reorder and watch the canvas restack live; click a row → it selects on the
  canvas; press the trash button and the Delete key (after selecting a row) → the object is removed and
  the canvas updates; reordering a shape above text actually draws it above (free layering).
