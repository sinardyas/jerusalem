# `EditorChrome.swift`

> Reusable visual chrome for the slide editor: the bottom status bar, the snap-feedback toast (plus its controller), and the dotted desk backdrop behind the stage.

**Location:** `Sources/Jerusalem/Editor/EditorChrome.swift`
**Role:** SwiftUI views + one small `@Observable` controller class

## What it does (plain English)

This file is a grab-bag of small, reusable pieces of "chrome" — the framing UI around the actual slide canvas. None of them edit a slide's content directly; they decorate the editor and surface feedback.

There are four pieces. `SlideStatusBar` is the strip along the bottom of the editor (autosave indicator, aspect ratio, pixel size, three checkboxes for canvas helpers, and a zoom readout). `EditorToastCenter` is a tiny controller that holds the "snapped!" message and auto-clears it after ~1 second. `EditorToast` is the floating capsule near the top that displays whatever `EditorToastCenter` is currently holding. `EditorDeskBackdrop` is the soft dot-grid "desk" drawn behind the slide stage.

The toast pair is the interesting one: the canvas (a different file) calls `toastCenter.show("Snapped to center")` when an element snaps to a guide, and the `EditorToast` view re-renders to fade the capsule in and out. This is the classic "one object holds state, one view displays it" split.

## Swift you'll meet in this file

- `struct SomeView: View { var body: some View { ... } }` — a SwiftUI view is a value-type struct, like a React function component; `body` is the returned JSX. TS analog: `function SomeView(): JSX.Element { return (...) }`. `some View` is an opaque return type meaning "returns some JSX element."
- `let x` = `const x`; `var x` = `let x` (reassignable).
- `@Binding var snapToGrid: Bool` — a two-way prop, like passing `{ snapToGrid, setSnapToGrid }` down from a parent so this view can write back into it. TS analog: a prop pair.
- `$snapToGrid` — the Binding "setter handle" you hand to a control like `Toggle`. TS analog: the `{ value, onChange }` you spread onto an input.
- `@MainActor @Observable final class` — a reference type (like a JS class instance, shared not copied) whose mutable properties are observed by SwiftUI; `@MainActor` pins it to the UI thread. TS analog: a small store class whose fields trigger re-render.
- `@Bindable var center` — lets a view make Bindings (`$center.message`) out of an `@Observable` object's fields, and re-render when they change. TS analog: a store passed as a prop, with `{ value: center.message, onChange: v => center.message = v }` derivable from it.
- Layout: `HStack` = a row (`<Row>`, flex row), `VStack` = a column (`<Column>`), `Spacer()` = a flex spacer (`<Spacer/>`) that pushes siblings apart.
- View modifiers chained with dots (`.font().foregroundStyle().padding()`) = applying styles/props, read top-down like nested wrappers — order matters.
- `Task { ... }` = an async block (like an async IIFE); `Task.sleep(nanoseconds:)` = `await sleep(ms)`. `[weak self]` avoids a retain cycle (roughly: "don't keep this object alive just for the timer").
- `Optional` `String?` = `string | null`; `if let message = center.message { ... }` unwraps it (renders only when non-null) — TS analog `{center.message != null && ...}`.

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

**TypeScript equivalent**

```tsx
<Row style={{ gap: 14 }}>
  <Row style={{ gap: 4 }}>
    <Icon name="checkmark.circle.fill" style={{ color: "green" }} /> {/* analogy: SF Symbol icon */}
    <Text>Autosaved</Text>
  </Row>
  {divider}
  <Text>{aspectLabel}</Text>
  {divider}
  <Text>{`${Math.round(pixelSize.width)}×${Math.round(pixelSize.height)} px`}</Text>
  {/* ... */}
</Row>
```

**Swift syntax:**
- `struct SlideStatusBar: View { var body: some View { ... } }` — declares a view; maps to `function SlideStatusBar(): JSX.Element`. `body` is the render output, `some View` = "some JSX element."
- `\(...)` inside a string — string interpolation, like `${...}` in a template literal.
- `Int(x.rounded())` — round then cast to integer; TS `Math.round(x)`.

`Image(systemName:)` is an SF Symbol (Apple's built-in icon font), the green check meaning "your work is saved." `divider` is a private computed property returning a thin 1pt rectangle — a reusable vertical separator. The three canvas toggles are checkboxes bound to props the parent owns:

```swift
Toggle(isOn: $snapToGrid) { Text("Snap to grid") }
    .toggleStyle(.checkbox)
```

**TypeScript equivalent**

```tsx
<label>
  <input
    type="checkbox"
    checked={snapToGrid}
    onChange={e => setSnapToGrid(e.target.checked)}
  />
  Snap to grid
</label>
```

**Swift syntax:**
- `Toggle(isOn: $snapToGrid) { Text(...) }` — `$snapToGrid` is the two-way binding (the `{checked, onChange}` pair); the trailing `{ ... }` is the label content (a view-builder closure, like `children`).
- `.toggleStyle(.checkbox)` — `.checkbox` is shorthand for `ToggleStyle.checkbox` (type inferred from the dot).

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

**TypeScript equivalent**

```ts
class EditorToastCenter {
  message: string | null = null;
  private clearTask: { cancelled: boolean } | null = null;

  show(text: string): void {
    if (this.message === text) { this.scheduleClear(); return; } // already showing? reset timer
    this.message = text;
    this.scheduleClear();
  }
}
```

**Swift syntax:**
- `func show(_ text: String)` — the `_` means the argument has no external label, so callers write `show("hi")` not `show(text: "hi")`. TS just has `show(text)`.

`scheduleClear()` cancels any pending timer and starts a new one that waits 1 second, then sets `message = nil` back on the main thread. The "same message? just reset the timer" guard prevents flicker when you drag slowly past a snap line and `show` fires repeatedly.

```swift
private func scheduleClear() {
    clearTask?.cancel()
    clearTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled else { return }
        await MainActor.run { self?.message = nil }
    }
}
```

**TypeScript equivalent**

```ts
private scheduleClear(): void {
  this.clearTask?.cancel?.();          // analogy: $foo?.() is optional-call
  const token = { cancelled: false };
  this.clearTask = token;
  (async () => {
    await sleep(1000);
    if (token.cancelled) return;       // analogy: Task.isCancelled
    this.message = null;               // back on the UI thread (MainActor.run)
  })();
}
```

**Swift syntax:**
- `clearTask?.cancel()` — optional chaining (`?.`): call `cancel()` only if `clearTask` isn't nil. TS `clearTask?.cancel()`.
- `try? await ...` — `try?` turns a throwing call into an optional (swallows the error → `nil`); TS analog: a `try/catch` that ignores the error.
- `guard !Task.isCancelled else { return }` — early-exit guard; TS `if (cancelled) return;`.
- `[weak self]` — capture list avoiding a retain cycle; no direct TS analog (GC handles it).

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

**TypeScript equivalent**

```tsx
{center.message != null && (
  <Text
    style={{
      paddingInline: 14,
      paddingBlock: 8,
      background: "rgba(0,0,0,0.7)",
      borderRadius: 9999,                 // analogy: Capsule() = pill shape
    }}
    transition="opacity + slideFromTop"   // analogy: .transition(...)
  >
    {center.message}
  </Text>
)}
```

**Swift syntax:**
- `if let message = center.message { ... }` — optional binding: render the block only when `message` is non-nil, with `message` now unwrapped. TS: `{center.message != null && (...)}`.
- `.opacity.combined(with: .move(edge: .top))` — composes two transitions; TS has no built-in equivalent, you'd hand-roll it.

`.transition(...)` plus `.animation(.easeOut..., value: center.message)` make the capsule fade and slide in/out whenever `message` changes. Two modifiers matter for correctness: `.allowsHitTesting(false)` means the toast never intercepts mouse clicks (drags pass through it to the canvas — TS analog `pointerEvents: "none"`), and the `VStack { ...; Spacer() }` pins it to the top.

### `EditorDeskBackdrop`

Uses SwiftUI's low-level `Canvas` (immediate-mode drawing, like an HTML `<canvas>`) to paint a grid of faint dots:

```swift
Canvas { context, size in
    let cols = Int((size.width / dotSpacing).rounded(.up))
    ...
    context.fill(Path(ellipseIn: rect), with: .color(dotColor.opacity(0.35)))
}
```

**TypeScript equivalent**

```tsx
<Canvas
  draw={(ctx, size) => {                        // analogy: trailing closure (context, size) in
    const cols = Math.ceil(size.width / dotSpacing);
    // ...
    ctx.fillEllipse(rect, dotColor.alpha(0.35));
  }}
/>
```

**Swift syntax:**
- `Canvas { context, size in ... }` — a trailing closure whose parameters (`context, size`) come before `in`. TS analog: `(context, size) => { ... }`.
- `.rounded(.up)` — ceiling; TS `Math.ceil`.

It loops columns × rows and fills a tiny ellipse at each grid point, over a system `underPageBackgroundColor`.

## How it connects

Nothing here touches SwiftData models. `SlideStatusBar`'s toggles are bound to view-level state owned by the editor (snap/guides/safe-area display preferences). `EditorToastCenter` is created by the editor and passed to both the canvas (which calls `show`) and `EditorToast` (which displays it). `EditorDeskBackdrop` sits behind the stage as pure decoration.

## Gotchas / why it matters

- The toast is deliberately invisible to hit-testing (`.allowsHitTesting(false)`) — if it weren't, it could swallow drag events mid-snap, which is exactly when it appears.
- The "same message resets timer instead of rebuilding" logic in `EditorToastCenter` is an anti-flicker measure; keep it if you refactor.
- `@MainActor` on the center plus `await MainActor.run { ... }` in the timer ensure the UI mutation happens on the main thread — required since the timer body runs in a background `Task`.
