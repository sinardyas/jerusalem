# `EditorChrome.swift`

> Reusable visual chrome for the slide editor: the bottom status bar, the snap-feedback toast (plus its controller), and the dotted desk backdrop behind the stage.

**Location:** `Sources/Jerusalem/Editor/EditorChrome.swift`
**Role:** SwiftUI views + one small `@Observable` controller class

## What it does (plain English)

This file is a grab-bag of small, reusable pieces of "chrome" — the framing UI around the actual slide canvas. None of them edit a slide's content directly; they decorate the editor and surface feedback.

There are four pieces. `SlideStatusBar` is the strip along the bottom of the editor (autosave indicator, aspect ratio, pixel size, three checkboxes for canvas helpers, and a zoom readout). `EditorToastCenter` is a tiny controller that holds the "snapped!" message and auto-clears it after ~1 second. `EditorToast` is the floating capsule near the top that displays whatever `EditorToastCenter` is currently holding. `EditorDeskBackdrop` is the soft dot-grid "desk" drawn behind the slide stage.

The toast pair is the interesting one: the canvas (a different file) calls `toastCenter.show("Snapped to center")` when an element snaps to a guide, and the `EditorToast` view re-renders to fade the capsule in and out. This is the classic "one object holds state, one view displays it" split.

## Swift you'll meet in this file

- `struct SomeView: View { var body: some View { ... } }` — a SwiftUI view is a value-type struct, like a React function component; `body` is the returned JSX. `some View` is an opaque return type meaning "returns some JSX element."
- `let x` = `const x`; `var x` = `let x` (reassignable).
- `@Binding var snapToGrid: Bool` — a two-way prop, like passing `[value, setValue]` down from a parent so this view can write back into it.
- `$snapToGrid` — the Binding "setter handle" you hand to a control like `Toggle`.
- `@MainActor @Observable final class` — a reference type (like a JS class instance, shared not copied) whose mutable properties are observed by SwiftUI; `@MainActor` pins it to the UI thread.
- `@Bindable var center` — lets a view make Bindings (`$center.message`) out of an `@Observable` object's fields, and re-render when they change.
- Layout: `HStack` = a row (flex row), `VStack` = a column, `Spacer()` = a flex spacer that pushes siblings apart.
- View modifiers chained with dots (`.font().foregroundStyle().padding()`) = applying styles/props, read top-down like nested wrappers.
- `Task { ... }` = an async block (like an async IIFE); `Task.sleep(nanoseconds:)` = `await sleep(ms)`. `[weak self]` avoids a retain cycle (roughly: "don't keep this object alive just for the timer").
- `Optional` `String?` = `string | null`; `if let message = center.message { ... }` unwraps it (renders only when non-null).

## Code walkthrough

### `SlideStatusBar`

Its `body` is one horizontal row:

```swift
HStack(spacing: 14) {
    HStack(spacing: 4) {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        Text("Autosaved")
    }
    divider
    Text(aspectLabel)
    divider
    Text("\(Int(pixelSize.width.rounded()))×\(Int(pixelSize.height.rounded())) px")
    ...
}
```

`Image(systemName:)` is an SF Symbol (Apple's built-in icon font), the green check meaning "your work is saved." `divider` is a private computed property returning a thin 1pt rectangle — a reusable vertical separator. The three canvas toggles are checkboxes bound to props the parent owns:

```swift
Toggle(isOn: $snapToGrid) { Text("Snap to grid") }
    .toggleStyle(.checkbox)
```

`Toggle` is an HTML `<input type=checkbox>`; `$snapToGrid` writes the user's click straight back into the parent's state. `Spacer()` then shoves the zoom readout to the far right. The whole row gets `.font(.caption).foregroundStyle(.secondary)` (small, dimmed text), padding, a `.background(.bar)` (system toolbar material), and a hairline `.overlay` line on top.

### `EditorToastCenter`

A small controller class, not a view:

```swift
func show(_ text: String) {
    if message == text { scheduleClear(); return }   // already showing? just reset the timer
    message = text
    scheduleClear()
}
```

`scheduleClear()` cancels any pending timer and starts a new one that waits 1 second, then sets `message = nil` back on the main thread. The "same message? just reset the timer" guard prevents flicker when you drag slowly past a snap line and `show` fires repeatedly.

### `EditorToast`

Displays whatever the center holds:

```swift
if let message = center.message {
    Text(message)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.black.opacity(0.7), in: Capsule())
        .transition(.opacity.combined(with: .move(edge: .top)))
}
```

`.transition(...)` plus `.animation(.easeOut..., value: center.message)` make the capsule fade and slide in/out whenever `message` changes. Two modifiers matter for correctness: `.allowsHitTesting(false)` means the toast never intercepts mouse clicks (drags pass through it to the canvas), and the `VStack { ...; Spacer() }` pins it to the top.

### `EditorDeskBackdrop`

Uses SwiftUI's low-level `Canvas` (immediate-mode drawing, like an HTML `<canvas>`) to paint a grid of faint dots:

```swift
Canvas { context, size in
    let cols = Int((size.width / dotSpacing).rounded(.up))
    ...
    context.fill(Path(ellipseIn: rect), with: .color(dotColor.opacity(0.35)))
}
```

It loops columns × rows and fills a tiny ellipse at each grid point, over a system `underPageBackgroundColor`.

## How it connects

Nothing here touches SwiftData models. `SlideStatusBar`'s toggles are bound to view-level state owned by the editor (snap/guides/safe-area display preferences). `EditorToastCenter` is created by the editor and passed to both the canvas (which calls `show`) and `EditorToast` (which displays it). `EditorDeskBackdrop` sits behind the stage as pure decoration.

## Gotchas / why it matters

- The toast is deliberately invisible to hit-testing (`.allowsHitTesting(false)`) — if it weren't, it could swallow drag events mid-snap, which is exactly when it appears.
- The "same message resets timer instead of rebuilding" logic in `EditorToastCenter` is an anti-flicker measure; keep it if you refactor.
- `@MainActor` on the center plus `await MainActor.run { ... }` in the timer ensure the UI mutation happens on the main thread — required since the timer body runs in a background `Task`.
