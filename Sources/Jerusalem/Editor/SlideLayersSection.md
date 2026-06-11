# `SlideLayersSection.swift`

> The left-rail "Layers" panel: a draggable, selectable, front-at-top list of the slide's objects, where drag restacks z-order and a trash button (or Delete key) removes an object. Plus the pure z-order math it uses.

**Location:** `Sources/Jerusalem/Editor/SlideLayersSection.swift`
**Role:** SwiftUI view + a pure helper enum (`SlideLayers`) + a private `LayerRow` view

## What it does (plain English)

This is the layer stack you'd recognize from any design tool. It lists every object on the current slide with the front-most at the top, lets you drag rows to restack them, click a row to select it (kept in sync with the canvas selection), and delete an object via the per-row trash button or the Delete key.

Because the renderer draws strictly in `order`, dragging a row to a new position has to rewrite every element's `order`. That math is split out into a pure `SlideLayers` enum so it can be unit-tested without UI. The panel deliberately lives in the **left** rail, not the right inspector: selecting an object there doesn't reshuffle the panel, and being outside the inspector's `ScrollView` means the list scrolls and selects natively.

## Swift you'll meet in this file

- `enum SlideLayers { static func reorder(...) }` — a caseless enum used purely as a namespace for a static function (the project's convention for pure, testable logic).
- `@Bindable var slide: Slide` — the SwiftData model whose elements are listed/reordered.
- `@Binding var selection: PersistentIdentifier?` — a two-way prop carrying the selected element's id (`null` when nothing is selected); shared with the canvas so both stay in sync.
- `var onDelete: (SlideElement) -> Void` / `var onChange: () -> Void` — callback props the parent supplies.
- `IndexSet` / `Int` in `move(fromOffsets:toOffset:)` — SwiftUI's drag-reorder gives you the moved source rows and a destination index; `Array.move` mutates in place.
- `slide.orderedElements.reversed()` — the model's order-sorted list, flipped so front is first.
- Controls/containers: `List(selection:)` = a selectable list (`<ul>` with selection state) bound to `$selection`; `ForEach(_, id:)` = `.map` over rows; `.onMove { }` = drag-to-reorder handler; `.onDeleteCommand` = Delete-key handler; `ContentUnavailableView` = a built-in empty-state placeholder; `.tag(...)` associates a row with its selectable value.
- `private struct LayerRow` — a file-private sub-view for one row.
- Tuple return `(symbol: String, color: Color)` for the per-kind glyph.

## Code walkthrough

### `SlideLayers.reorder` (the pure math)

```swift
static func reorder(frontFirst elements: [SlideElement],
                    from source: IndexSet, to destination: Int) {
    var arr = elements
    arr.move(fromOffsets: source, toOffset: destination)
    let count = arr.count
    for (index, element) in arr.enumerated() {
        element.order = count - 1 - index
    }
}
```

It receives the list as the UI shows it (front-first), applies SwiftUI's move, then rewrites `order` so the **back-most gets 0 and front-most gets `count - 1`** — the inverse of the list index, because the list is front-first but `order` counts up from the back. Same "rewrite `order` from final positions" idea as `SlideArrangeSection`.

### The panel `body`

A header, then either an empty state or the list:

```swift
private var layers: [SlideElement] { Array(slide.orderedElements.reversed()) }
```

If there are no elements, it shows a friendly placeholder:

```swift
ContentUnavailableView("No Objects",
                       systemImage: "square.3.layers.3d.slash",
                       description: Text("Add a text, image, or shape from the toolbar."))
```

Otherwise, the selectable, draggable list:

```swift
List(selection: $selection) {
    ForEach(layers, id: \.persistentModelID) { element in
        LayerRow(element: element) { onDelete(element) }
            .tag(element.persistentModelID as PersistentIdentifier?)
    }
    .onMove { source, destination in
        SlideLayers.reorder(frontFirst: layers, from: source, to: destination)
        onChange()
    }
}
.listStyle(.sidebar)
.onDeleteCommand(perform: deleteSelected)
```

`List(selection: $selection)` two-way-binds the selected row's id to `selection`, so clicking here updates the canvas (and vice versa). Each row is `.tag`-ged with its `persistentModelID` so selection can identify it. `.onMove` runs the pure reorder then `onChange()`. `.onDeleteCommand` wires the Delete key to `deleteSelected`.

`deleteSelected` finds the selected element and forwards it:

```swift
guard let selection,
      let element = slide.elements.first(where: { $0.persistentModelID == selection })
else { return }
onDelete(element)
```

### `LayerRow`

One row = a colored kind glyph, the object's `layerName`, a `Spacer`, and a trash button:

```swift
Image(systemName: glyph.symbol)
    .frame(width: 18, height: 18)
    .background(glyph.color, in: RoundedRectangle(cornerRadius: 4))
Text(element.layerName).lineLimit(1).truncationMode(.middle)
Spacer(minLength: 4)
Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
```

`glyph` switches on `element.kind` to give text→orange `textformat`, image→blue `photo`, shape→purple `square.on.circle` — intentionally matching `InspectorHeaderChip`.

## How it connects

It reads/reorders the `slide`'s `SlideElement`s and shares the selection (`PersistentIdentifier?`) with the editor and canvas via `@Binding`. The parent supplies `onDelete` (which actually removes the element through the `ModelContext`, making it undoable) and `onChange` (fired after a drag-reorder). Reordering changes `element.order`, which the shared `SlideRenderer` reads to draw layers in the right stacking order.

## Gotchas / why it matters

- **Front-first list, back-first `order`.** The list shows front at top, but `order` counts up from the back, so `reorder` writes `order = count - 1 - index`. Get this inversion wrong and the visual stack flips. The pure helper exists precisely so this is unit-tested.
- **Reordering/deleting goes through `onChange`/`onDelete`** so it's persisted and undoable, and flips `Slide.isManuallyEdited` (telling `ContentRebuilder` to leave the slide alone).
- The panel lives in the left rail on purpose: nesting it in the inspector's `ScrollView` would fight the list's own scrolling/selection and reshuffle on selection. Keep it where it is.
- `selection` is shared state — both this list and the canvas write it, so a click in either place reflects in the other.
