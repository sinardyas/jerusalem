# `DefaultTheme.swift`

> Defines the built-in "Default Dark" look and the helpers that copy a `Theme`'s style onto freshly created slides/elements (and back).

**Location:** `Sources/Jerusalem/Content/DefaultTheme.swift`
**Role:** catalog/data (an `extension` on the `Theme` model)

## What it does (plain English)

When new content is auto-generated (a song or sermon split into slides by `ContentRebuilder`), each slide needs *some* visual style or it would render as bare text. This file provides that style. It's a Swift `extension` that bolts extra functions onto the existing `Theme` model — it doesn't define a new type.

`makeDefault()` builds the canonical "Default Dark" theme: dark navy background, white centered Avenir Next at 56pt, sized against the renderer's 1920×1080 reference. `apply(to:)` (two overloads) stamps a theme's values onto a fresh `Slide`'s background and a fresh `SlideElement`'s typography. `copy(from:)` does the reverse — it reads a styled element back *into* the theme, powering the inspector's "set as default style for new slides" action.

It sits at the tail of the pipeline: `ContentRebuilder.materialize` calls `Theme.makeDefault()` (when an item has no theme) and `theme.apply(to:)` on every slide and element it creates.

## Swift you'll meet in this file

| Swift | JS/TS equivalent |
|---|---|
| `extension Theme { ... }` | adding methods to an existing class from another file — like augmenting a class via a mixin / `Object.assign(Theme.prototype, {...})` |
| `static func makeDefault() -> Theme` | a static factory: `Theme.makeDefault()`, like `Theme.makeDefault()` returning a new instance |
| `func apply(to slide: Slide)` | an instance method; `to slide` is an external/internal label — call site reads `theme.apply(to: slide)` |
| two `apply(to:)` overloads | method overloading by parameter type — Swift picks `Slide` vs `SlideElement` automatically |
| `theme.backgroundColorHex = "#0F172A"` | setting a property; the hex string is the stored color |
| `element.fontSize = fontSize` | RHS `fontSize` is the theme's own property (implicit `self.fontSize`) |

## Code walkthrough

**The factory.** Just sets five properties on a new `Theme`:

```swift
static func makeDefault() -> Theme {
    let theme = Theme(name: "Default Dark")
    theme.backgroundColorHex = "#0F172A"   // dark navy
    theme.fontName = "Avenir Next"
    theme.fontSize = 56
    theme.textColorHex = "#FFFFFF"         // white
    return theme
}
```

**Apply to a slide.** Slides only carry a background, so this is a one-liner:

```swift
func apply(to slide: Slide) {
    slide.backgroundColorHex = backgroundColorHex
}
```

**Apply to an element.** This is the bulk of the file — it copies *every* typography and effect property from the theme onto a new text element (font, color, alignment, bold/italic/underline, shadow, stroke, auto-fit, line/letter spacing, etc.). Geometry (position/size) is deliberately left at the renderer's default centered frame:

```swift
func apply(to element: SlideElement) {
    element.fontName = fontName
    element.fontSize = fontSize
    element.colorHex = textColorHex
    element.alignment = alignment
    element.isBold = isBold
    // ... shadow, stroke, autoFit, spacing, etc.
}
```

**Copy back from an element.** The mirror image — reads a styled element's properties into the theme so future "Add Text" clicks inherit the look the user just dialed in:

```swift
func copy(from element: SlideElement) {
    fontName = element.fontName
    fontSize = element.fontSize
    textColorHex = element.colorHex
    // ... same property set, reversed direction
}
```

## How it connects

```
ContentRebuilder.materialize
        │
        ├─ item.theme ?? Theme.makeDefault()      // pick or build a theme
        ├─ theme.apply(to: slide)                 // background
        └─ theme.apply(to: element)               // typography on the text element
                                                        │
                                                        ▼
                                              renderer draws the styled slide

Inspector "set as default style"  ──▶  theme.copy(from: element)   // remember this look
```

Upstream, `ContentRebuilder` decides *what* text goes on each slide; this file decides *how it looks*. Downstream, the renderer reads the stamped properties off the `Slide`/`SlideElement` to draw the actual pixels.

## Gotchas / why it matters

- **Single default style.** "Default Dark" is the one place the app's out-of-the-box look is defined, so every auto-derived slide is consistent before anyone touches the editor.
- **Typography is themed; geometry is not.** `apply(to: element)` copies fonts/colors/effects but leaves the frame at the renderer's default centered position — so themed text always lands in the right place regardless of output resolution (the 1920×1080 reference handles scaling).
- **`copy(from:)` and `apply(to:)` must stay in sync.** They list the same property set in opposite directions; if you add a styling property to `SlideElement`, add it to *both* or the round-trip will silently drop it.
- **It's an `extension`, not a new model.** These functions live on the real `Theme` SwiftData model — handy to remember when searching for where `makeDefault`/`apply`/`copy` come from.
