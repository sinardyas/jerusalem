# `InspectorSection.swift`

> Three reusable inspector building blocks: a titled section container, a label-left/control-right row, and the header chip that names the selected object's type.

**Location:** `Sources/Jerusalem/Editor/InspectorSection.swift`
**Role:** reusable view components

## What it does (plain English)

This file holds the visual scaffolding that the individual inspector sections (Arrange, Background, Theme, …) are built from. None of these edit a model — they're layout wrappers that give the inspector a consistent look.

`InspectorSection` is the boxed-section pattern: an uppercase, dimmed, letter-spaced header (optionally with a faint suffix like "(slide)"), the section's content underneath, and a hairline `Divider` below. `InspectorRow` is the standard form row — a fixed-width label on the left, a control hugging the right edge. `InspectorHeaderChip` is the chip at the very top of the inspector: a colored, icon-stamped tile plus the name of whatever's selected ("Text Box", "Image", "Shape", or "Slide" when nothing's selected).

The first two use Swift generics so they can wrap *any* content/control you pass in — think of them as styled wrapper components that take `children`.

## Swift you'll meet in this file

- `struct InspectorSection<Content: View>: View` — a **generic** view; `<Content: View>` is a type parameter constrained to be a `View`, like a React component generic over its `children`'s type.
- `@ViewBuilder var content: Content` — the slotted children. `@ViewBuilder` lets the caller write a block of views (`InspectorSection(title: "X") { ...views... }`) and have them composed for you; the block is passed as a trailing closure (last-argument children).
- `var trailing: String? = nil` — an optional prop with a default; `String?` is `string | null`. `if let trailing { Text(trailing) }` renders it only when present.
- `let label: String`, `var labelWidth: CGFloat = 64` — required and defaulted props.
- Layout: `VStack(alignment: .leading)` = a left-aligned column; `HStack` = a row; `Spacer(minLength: 0)` = a flex spacer.
- Modifiers: `.font(...)`, `.tracking(0.5)` (letter-spacing), `.foregroundStyle(.secondary/.tertiary)` (dimming levels), `.frame(width:alignment:)`, `.padding(...)`.
- `Divider()` = an `<hr>`. `RoundedRectangle(...).fill(...).overlay(...)` builds the icon tile. `Image(systemName:)` is an SF Symbol icon.
- The descriptor uses a returned **tuple** `(glyph: String, color: Color, title: String)` — like returning an object literal `{ glyph, color, title }`.

## Code walkthrough

### `InspectorSection`

```swift
VStack(alignment: .leading, spacing: 10) {
    HStack(spacing: 6) {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
        if let trailing {
            Text(trailing).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        Spacer(minLength: 0)
    }
    content
}
.frame(maxWidth: .infinity, alignment: .leading)
.padding(.horizontal, 16).padding(.vertical, 12)
Divider()
```

The header row is uppercased, semibold-11pt, letter-spaced, and dimmed (`.secondary`); the optional `trailing` suffix is even dimmer (`.tertiary`). `Spacer(minLength: 0)` pushes the header text left. Then `content` — whatever the caller passed — is laid out below. The `Divider()` sits *after* the `VStack` (outside the padding), so it spans the full width as a section separator.

### `InspectorRow`

```swift
HStack(spacing: 10) {
    Text(label).font(.callout).frame(width: labelWidth, alignment: .leading)
    control.frame(maxWidth: .infinity, alignment: .trailing)
}
```

Fixed-width label on the left, control filling the rest and right-aligned. This gives every form row the same gutter so labels line up.

### `InspectorHeaderChip`

```swift
HStack(spacing: 8) {
    RoundedRectangle(cornerRadius: 5)
        .fill(descriptor.color)
        .frame(width: 20, height: 20)
        .overlay(Image(systemName: descriptor.glyph)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white))
    Text(descriptor.title).font(.headline)
    Spacer(minLength: 0)
}
```

A 20×20 colored tile with a white glyph overlaid, then the type name. The look is driven by `descriptor`, which switches on the selected element's `kind`:

```swift
switch kind {
case .text:  return ("textformat", .orange, "Text Box")
case .image: return ("photo", .blue, "Image")
case .shape: return ("square.on.circle", .purple, "Shape")
case nil:    return ("rectangle.on.rectangle", .gray, "Slide")
}
```

`kind` is a `SlideElementKind?`; `nil` means nothing is selected, so it shows the gray "Slide" chip.

## How it connects

These are the shared primitives the real sections use. For example `SlideArrangeSection`, `SlideBackgroundSection`, and `SlideThemeSection` all wrap their controls in `InspectorSection(title: ...) { ... }`. The header chip's per-kind glyph/color is deliberately mirrored by `SlideLayersSection`'s `LayerRow` so an element looks the same in the layers list and the inspector. `InspectorHeaderChip` reads the selection's `SlideElementKind` but writes nothing.

## Gotchas / why it matters

- These are presentation-only; no Bindings, no `ModelContext`. Edits happen inside the `content`/`control` you hand them, not here.
- The `Divider()` is intentionally outside the padded `VStack` so it runs edge-to-edge. If you move it inside, the separator will be inset and look wrong.
- The chip's `kind: nil` case is what makes "nothing selected" render as "Slide" — keep that branch in sync with `InspectorTab.onSelectionChange` (no selection → Slide tab).
