# `SlideArrangeSection.swift`

> The inspector's "Arrange" section: a 2×2 grid of percent fields for X/Y/W/H plus a Front/Forward/Back/Send-to-Back button row, editing the selected element's normalized frame and z-order.

**Location:** `Sources/Jerusalem/Editor/SlideArrangeSection.swift`
**Role:** SwiftUI view

## What it does (plain English)

This is the section where you type exact numbers for the selected object's position and size, and restack it relative to other objects. The four fields show X, Y, Width, Height as percentages, because element frames are stored normalized in `0...1`; the field formats `0.5` as `50.0%` and parses your typed `50%` back to `0.5`.

Every numeric edit is clamped through `SlideGeometry.clamped` (so the element can't go off-slide or shrink below a minimum), then written back onto the `SlideElement`. The four buttons reorder the element among its siblings using pure helpers in `SlideGeometry` and rewrite each element's `order`. Both kinds of edit call `onChange()`, which is how the rest of the app learns the slide was hand-edited (flipping `Slide.isManuallyEdited`) and re-renders/re-arms.

## Swift you'll meet in this file

- `@Bindable var slide: Slide` / `@Bindable var element: SlideElement` — `@Bindable` wraps SwiftData `@Model` objects so you can both read their fields and make `$`-Bindings from them; the section edits the `element` and reorders within the `slide`.
- `var onChange: () -> Void` — a callback prop the parent supplies (`() => void`), fired after any edit.
- `Binding<Double>` / `Binding<String>` — two-way value handles. This file builds **custom** bindings with `Binding(get:set:)` — an object with a getter and a setter, so reads and writes can transform the value (percent ↔ fraction, clamp on write).
- `WritableKeyPath<SlideGeometry.Frame, Double>` — a key path, like a typed pointer to a field (e.g. "the `.x` field"); `frame[keyPath: kp]` reads/writes it. Comparable to a typed property accessor.
- `private func percentField(_ label:value:) -> some View` — a helper that returns a view (a sub-component factory).
- `private enum Movement { case front, forward, backward, back }` — a local enum for the four reorder directions.
- `element.persistentModelID` — SwiftData's stable identity for a model row (used to find the element in the ordered list).
- Controls: `TextField("", text:)` = a text `<input>`; `Button { action } label: { ... }` = a button with custom content; `.help("...")` = a tooltip.

## Code walkthrough

The `body` wraps everything in the shared `InspectorSection`:

```swift
InspectorSection(title: "Arrange") {
    HStack(spacing: 8) {
        percentField("X", value: bindingFor(\.x, min: 0))
        percentField("Y", value: bindingFor(\.y, min: 0))
    }
    HStack(spacing: 8) {
        percentField("W", value: bindingFor(\.width, min: SlideGeometry.defaultGridStep))
        percentField("H", value: bindingFor(\.height, min: SlideGeometry.defaultGridStep))
    }
    ...
}
```

`\.x`, `\.width`, etc. are key paths into a `SlideGeometry.Frame`. Width/Height get a non-zero minimum (`defaultGridStep`) so an element can't collapse to nothing.

### Percent display ↔ stored fraction

`percentField` is just a label + a `TextField` whose text is a derived string binding:

```swift
TextField("", text: percentText(value))
    .textFieldStyle(.roundedBorder)
    .frame(maxWidth: 80)
```

`percentText` converts between the stored `Double` and the on-screen `"%"` string:

```swift
Binding(
    get: { String(format: "%.1f%%", binding.wrappedValue * 100) },
    set: { newValue in
        let stripped = newValue.trimmingCharacters(in: CharacterSet(charactersIn: "%, "))
        guard let parsed = Double(stripped) else { return }
        binding.wrappedValue = parsed / 100.0
    })
```

Read multiplies by 100 and appends `%`; write strips `%`/spaces, and if it parses, divides by 100 back into the underlying `Double` binding. A bad input (`guard let ... else { return }`) is silently ignored.

### The geometry binding (clamp on write)

`bindingFor` is where the clamping lives:

```swift
Binding(
    get: { currentFrame[keyPath: keyPath] },
    set: { newValue in
        var f = currentFrame
        f[keyPath: keyPath] = newValue
        let clamped = SlideGeometry.clamped(f, minSize: min)
        element.x = clamped.x
        element.y = clamped.y
        element.width = clamped.width
        element.height = clamped.height
        onChange()
    })
```

It reads the current frame, sets just the edited field, runs the whole frame through `SlideGeometry.clamped`, then writes all four fields back onto the `element` and calls `onChange()`. `currentFrame` simply snapshots the element's four numbers into a `SlideGeometry.Frame` value.

### Reorder buttons

Each button calls `reorder(_:)` with a `Movement`:

```swift
Button { reorder(.front) } label: {
    Image(systemName: "square.3.layers.3d.top.filled")
}.help("Bring to Front")
```

`reorder` finds the element's current index in `slide.orderedElements`, asks `SlideGeometry` for the new index arrangement, then rewrites each element's `order` from its resulting position:

```swift
case .front:    newIndices = SlideGeometry.movedToFront(currentIndex, in: indices)
...
for (position, oldIndex) in newIndices.enumerated() {
    ordered[oldIndex].order = position
}
onChange()
```

The comment explains the trick: it reorders *indices* (a stable identity), then re-derives every `order` from the final positions, which sidesteps any duplicate-`order` edge case.

## How it connects

It edits one `SlideElement`'s frame (`x/y/width/height`) and the relative `order` of all elements on the `slide`. The parent inspector hosts it under the "Arrange" tab and supplies `slide`, `element`, and `onChange`. `onChange()` is the hook the editor uses to mark `Slide.isManuallyEdited`, persist via `ModelContext` (undoable), and re-render the canvas/thumbnail. The actual math (clamp, raise/lower/front/back) is delegated to the pure, tested `SlideGeometry` namespace.

## Gotchas / why it matters

- **Normalized coordinates:** the fields are percentages of the slide, not pixels. `0.5` ⇒ `50%`; a value at a 1920×1080 reference is irrelevant here (that's font size, elsewhere). Keep new geometry in `0...1`.
- **Clamp on every write** is what keeps an element on-slide and above the minimum size — don't bypass `SlideGeometry.clamped` by writing fields directly.
- The reorder approach (rewrite `order` from final positions, keyed by `persistentModelID`) is deliberate to avoid duplicate `order` bugs; it's mirrored by `SlideLayers.reorder`. Touching either flips `isManuallyEdited` via `onChange()`, telling `ContentRebuilder` to leave this slide alone.
