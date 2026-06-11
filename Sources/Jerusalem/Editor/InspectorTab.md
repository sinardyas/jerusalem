# `InspectorTab.swift`

> A small enum naming the three inspector tabs (Format / Arrange / Slide) and the pure rule for which tab to auto-focus when the canvas selection changes.

**Location:** `Sources/Jerusalem/Editor/InspectorTab.swift`
**Role:** enum/model (pure value type, no UI)

## What it does (plain English)

The inspector (the right-hand panel) is split into three tabs instead of one long scrolling column: **Format** (the selected object's styling — font, color, etc.), **Arrange** (its position, size, and layer order), and **Slide** (slide-wide settings like background and theme). This file defines those three tabs as an `enum` and gives each a stable id and a display title.

It also encodes one tiny behavior rule: when the user selects an object on the canvas, jump to `format`; when they deselect (nothing selected), jump to `slide`. That's the whole of `onSelectionChange`. Per the project convention of pushing decidable rules into pure types, this lives here — with no SwiftUI import — so it's unit-testable on its own.

## Swift you'll meet in this file

- `enum InspectorTab: String, CaseIterable, Identifiable` — a TS-style enum/union. `: String` gives each case a raw string value (the `rawValue`). `CaseIterable` means you can iterate all cases via `InspectorTab.allCases` (like `Object.values(Enum)`), handy for building a tab bar. `Identifiable` means it has an `id` (so `ForEach` can track it).
- `case format, arrange, slide` — the three members.
- `var id: String { rawValue }` — a computed property (a getter); satisfies `Identifiable`.
- `var title: String { switch self { ... } }` — a computed getter using a `switch`; in Swift each branch's expression is the returned value (no explicit `return` needed here).
- `static func onSelectionChange(hasSelection: Bool) -> InspectorTab` — a static (class-level) function; `hasSelection ? .format : .slide` is a ternary. `.format` is shorthand for `InspectorTab.format` (the type is inferred).

## Code walkthrough

The enum and its raw values:

```swift
enum InspectorTab: String, CaseIterable, Identifiable {
    case format, arrange, slide

    var id: String { rawValue }
```

Because it's `: String`, `InspectorTab.format.rawValue == "format"`, and `id` just reuses that — so a `Picker`/tab bar can key on it.

`title` maps each case to its human label:

```swift
var title: String {
    switch self {
    case .format:  "Format"
    case .arrange: "Arrange"
    case .slide:   "Slide"
    }
}
```

And the selection rule:

```swift
static func onSelectionChange(hasSelection: Bool) -> InspectorTab {
    hasSelection ? .format : .slide
}
```

Note the doc comment's important caveat: this is consulted *only* when the selection actually changes. If the user manually clicks the "Arrange" tab and keeps the same object selected, nothing forces them off it.

## How it connects

The inspector container view holds the currently-active `InspectorTab` (likely as `@State`), renders a tab bar from `InspectorTab.allCases`, and shows the matching section views (Format → text/style controls; Arrange → `SlideArrangeSection`; Slide → `SlideBackgroundSection` / `SlideThemeSection`). When the canvas selection changes, that view calls `InspectorTab.onSelectionChange(hasSelection:)` and switches tabs accordingly.

## Gotchas / why it matters

- The "only on selection change" contract matters for UX: it keeps a manually-chosen tab sticky. If you wire this up so it runs on every render, you'll yank the user off their chosen tab — don't.
- Keeping it free of SwiftUI is deliberate (project convention): the auto-switch rule can be covered by a plain unit test, no view needed.
