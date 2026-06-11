# `ZoomBar.swift`

> The canvas's bottom-left zoom control — a `− NN% +` capsule — plus `CanvasZoomMath`, the single shared source of zoom bounds and math that the buttons, trackpad pinch, and ⌘-scroll all funnel through.

**Location:** `Sources/Jerusalem/Editor/ZoomBar.swift`
**Role:** SwiftUI view + pure math namespace

## What it does (plain English)

Two small things in one file.

`CanvasZoomMath` is a tiny pure namespace (a caseless `enum`) that owns the zoom **range** (0.5×–2.0×) and the three ways zoom changes — clamp a value, apply a pinch magnification, apply a ⌘-scroll delta. Everything that can change zoom routes through it, so the button steps, trackpad pinch, and ⌘-scroll never disagree about limits or behavior.

`ZoomBar` is the visible control: a material "capsule" pill at the bottom-left of the stage with a minus button, the current percentage, and a plus button. It's bound two-way to the editor's `zoom` state, so its buttons and the pinch/scroll gestures all drive the same value.

## Swift you'll meet in this file

- `enum CanvasZoomMath { static let range … }` — caseless enum = pure-function namespace, like `export const CanvasZoomMath = { … }`.
- `ClosedRange<CGFloat> = 0.5...2.0` — an inclusive range value (`0.5...2.0`), with `.lowerBound`/`.upperBound`.
- `static func clamp(_ value: CGFloat) -> CGFloat` — `_` = unlabeled first arg; `CGFloat` = a `number`.
- `struct ZoomBar: View { @Binding var zoom: CGFloat }` — SwiftUI view; `@Binding` = a two-way prop ([value, setValue] from the parent).
- `HStack(spacing: 8) { … }` = a row; `Button { … } label: { … }` = a button (action closure + label); `Image(systemName: "minus")` = SF Symbol.
- `.disabled(zoom <= range.lowerBound + 0.001)` = conditionally disable; `Int((zoom * 100).rounded())` = round to a whole percent.
- `.background(.regularMaterial, in: Capsule())` = a translucent blurred pill background; `.overlay(Capsule().strokeBorder(…))` / `.shadow(…)` = styling wrappers.

## Code walkthrough

### `CanvasZoomMath` — shared bounds + math

```swift
enum CanvasZoomMath {
    static let range: ClosedRange<CGFloat> = 0.5...2.0

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, value))
    }
    /// Pinch: `magnification` is the incremental factor of one magnify event.
    static func applying(magnify magnification: CGFloat, to zoom: CGFloat) -> CGFloat {
        clamp(zoom * (1 + magnification))
    }
    /// ⌘-scroll: `delta` is the already-scaled additive zoom change.
    static func applying(scroll delta: CGFloat, to zoom: CGFloat) -> CGFloat {
        clamp(zoom + delta)
    }
}
```

- `clamp` pins any value into 0.5…2.0.
- `applying(magnify:)` treats pinch as **multiplicative** — `magnification` is a small incremental factor (e.g. `0.1`), so `zoom * (1 + 0.1)` scales up 10% — then clamps. This is the natural feel for a pinch.
- `applying(scroll:)` treats ⌘-scroll as **additive** — the delta is already scaled by the caller (`SlideEditorView` multiplies the raw scroll by `0.004`/`0.04`), so this just adds and clamps.

`SlideEditorView.applyZoom` calls these two; `ZoomBar`'s buttons call `clamp`. One namespace, three entry points, identical limits.

### `ZoomBar` — the capsule control

```swift
struct ZoomBar: View {
    @Binding var zoom: CGFloat
    private let range = CanvasZoomMath.range
    private let step: CGFloat = 0.1

    var body: some View {
        HStack(spacing: 8) {
            Button { set(zoom - step) } label: { Image(systemName: "minus") }
                .disabled(zoom <= range.lowerBound + 0.001)
            Text("\(Int((zoom * 100).rounded()))%")
                .font(.callout.monospacedDigit()).frame(width: 42)
            Button { set(zoom + step) } label: { Image(systemName: "plus") }
                .disabled(zoom >= range.upperBound - 0.001)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    private func set(_ value: CGFloat) { zoom = CanvasZoomMath.clamp(value) }
}
```

A minus button (steps `zoom` down by `0.1`), a monospaced percentage readout (so it doesn't jitter as digits change), and a plus button. Each button is disabled at its end of the range (`+ 0.001` / `- 0.001` guards floating-point fuzz). Every change goes through `set`, which clamps via `CanvasZoomMath`. The styling wraps it all in a translucent `.regularMaterial` capsule with a hairline border and a soft shadow so it floats over the stage.

## How it connects

- **`SlideEditorView`** owns `zoom` and places `ZoomBar(zoom: $zoom)` at the stage's bottom-left. The canvas frame is sized `× zoom`, so changing it scales the whole stage.
- **`CanvasZoomMath`** is the shared brain: the bar's buttons (`clamp`), trackpad pinch (`applying(magnify:)`), and ⌘-scroll (`applying(scroll:)`) all converge here, so no input can exceed 50–200% or feel inconsistent.

## Gotchas / why it matters

- **One source of truth for limits.** Don't hardcode 0.5/2.0 anywhere else — route through `CanvasZoomMath.range`/`clamp` so the button, pinch, and scroll paths stay in lockstep.
- **Pinch is multiplicative, scroll is additive.** They're intentionally different curves; the scroll delta is pre-scaled by the caller, the pinch factor is not.
- **Monospaced digits + epsilon guards.** Small details that keep the readout from shifting and the buttons from getting stuck "almost" at a bound due to float error.
