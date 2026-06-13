# `InlineTextEditOverlay.swift`

> A floating text editor positioned directly over a text element on the canvas, so the user can edit slide text in place; commits on Enter/focus-loss and cancels on Escape.

**Location:** `Sources/Jerusalem/Editor/InlineTextEditOverlay.swift`
**Role:** SwiftUI view (an overlay)

## What it does (plain English)

This is the editor's version of the web `contenteditable`. When you double-click a text box on the slide canvas, this overlay appears exactly where that text box lives, lets you retype it, and then hands the new text back to the editor. While it's up, it dims and blocks the canvas behind it so stray clicks don't deselect or drag anything.

Crucially, it does **not** write to the model itself. It keeps a local `draft` string, and when you commit it calls `onCommit(draft)` — a callback supplied by the parent. The parent is the one that applies the change through the SwiftData undo manager, so a single Cmd-Z reverts the whole edit. Escape calls `onCancel()` and the original text stays.

It takes presentation props (`frame`, `font`, `textColor`, `alignment`) so the editable field visually matches the element it's covering — same place, same font, same alignment.

## Swift you'll meet in this file

- `let initialText: String` / `var onCommit: (String) -> Void` — `let` is `const`; `(String) -> Void` is a function type, i.e. a callback prop `(s: string) => void`.
- `@State private var draft: String` — local component state, exactly like `const [draft, setDraft] = useState(...)`.
- `@FocusState private var focused: Bool` — a special binding tracking whether a field has keyboard focus; you can read it and set it to programmatically focus. TS analog: `const [focused, setFocused] = useState(false)` plus an imperative `inputRef.focus()`.
- A custom `init(...)` with `_draft = State(initialValue: initialText)` — a constructor that seeds the `@State` from a prop. (`_draft` is the underlying storage of the `@State`.) `@escaping` on the callback params means "this closure outlives the call" (it's stored). TS analog: `useState(() => initialText)` as the lazy initial value.
- `$draft`, `$focused` — Binding projections handed to controls (`{value, onChange}` pairs).
- `CGRect`, `CGPoint` — geometry structs; `frame.midX` / `frame.midY` are the center coordinates.
- `@ViewBuilder private var editor: some View` — a computed sub-view; `@ViewBuilder` lets you write multiple child views without explicitly wrapping them (like returning a fragment).
- Layout/controls: `ZStack` = layered/absolutely-stacked children (`<Layered>`); `TextEditor` = a multi-line `<textarea>`; `Button(action:)` = `<button onClick>`; `.overlay(...)` draws a view on top of another.

## Code walkthrough

The outermost `body` is a nearly-invisible full-area shield with the editor floated on top:

```swift
Color.black.opacity(0.001)
    .contentShape(Rectangle())
    .onTapGesture { commit() }
    .overlay(
        editor
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    )
    .onAppear { focused = true }
    .background(escapeKeyCatcher)
```

**TypeScript equivalent**

```tsx
<div
  style={{
    position: "absolute", inset: 0,
    background: "rgba(0,0,0,0.001)",   // near-invisible but hit-testable
  }}
  onClick={() => commit()}              // analogy: .onTapGesture { commit() }
>
  {/* analogy: .overlay(editor...) floated and centered over the element */}
  <div
    style={{
      position: "absolute",
      width: frame.width, height: frame.height,
      left: frame.midX, top: frame.midY,
      transform: "translate(-50%, -50%)", // .position() centers on the point
    }}
  >
    {editor}
  </div>
  {escapeKeyCatcher}                     {/* analogy: .background(...) */}
</div>
// analogy: .onAppear { focused = true } → useEffect(() => inputRef.current?.focus(), [])
```

**Swift syntax:**
- `struct InlineTextEditOverlay: View { var body: some View }` — view declaration; maps to `function InlineTextEditOverlay(props): JSX.Element`.
- `.onTapGesture { commit() }` — trailing-closure event handler; TS `onClick={() => commit()}`.
- `.position(x:y:)` — places a view by its center point; TS equivalent uses `translate(-50%,-50%)`.
- `.onAppear { ... }` — runs once when the view mounts; TS `useEffect(..., [])`.

The almost-transparent `Color.black.opacity(0.001)` plus `.contentShape(Rectangle())` makes the entire area tappable — a tap *outside* the field commits the edit (like clicking away). `.overlay(editor...)` places the real editor sized to `frame.width/height` and centered at `frame.midX/midY`, i.e. exactly over the element. `.onAppear { focused = true }` auto-focuses the field so you can type immediately.

The `editor` sub-view layers a dark rounded backdrop, an accent border, and the text field:

```swift
ZStack {
    RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.4))
    RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1.5)
    TextEditor(text: $draft)
        .focused($focused)
        .font(font)
        .foregroundStyle(textColor)
        .multilineTextAlignment(alignment)
        .scrollContentBackground(.hidden)
        .padding(6)
        .onSubmit(commit)
}
```

**TypeScript equivalent**

```tsx
<Layered> {/* analogy: ZStack — children stacked back-to-front */}
  <div style={{ position: "absolute", inset: 0, borderRadius: 4, background: "rgba(0,0,0,0.4)" }} />
  <div style={{ position: "absolute", inset: 0, borderRadius: 4, border: "1.5px solid var(--accent)" }} />
  <textarea
    ref={inputRef}
    value={draft}                                  // analogy: TextEditor(text: $draft)
    onChange={e => setDraft(e.target.value)}
    style={{
      font, color: textColor,
      textAlign: alignment,                        // analogy: .multilineTextAlignment
      background: "transparent",                   // analogy: .scrollContentBackground(.hidden)
      padding: 6,
    }}
    onKeyDown={e => { if (e.key === "Enter") commit(); }} // analogy: .onSubmit(commit)
  />
</Layered>
```

**Swift syntax:**
- `@ViewBuilder private var editor: some View` — computed property returning a view; `@ViewBuilder` lets the body hold several children without a wrapper, like a fragment.
- `TextEditor(text: $draft)` — bound to the `$draft` binding; only `draft` updates as you type.
- `.focused($focused)` — wires the field's focus to the `$focused` binding (so setting `focused = true` focuses it).

`TextEditor(text: $draft)` is bound to local state — typing only updates `draft`. `.focused($focused)` ties it to the focus state. The passed-in `font`, `textColor`, and `alignment` make it look like the real element. `.scrollContentBackground(.hidden)` removes the editor's default opaque background so the dark rounded rect shows through. `.onSubmit(commit)` fires on Enter.

Escape is handled separately, because `TextEditor` doesn't report Escape via `.onSubmit`:

```swift
private var escapeKeyCatcher: some View {
    Button(action: cancel) { Color.clear }
        .keyboardShortcut(.escape, modifiers: [])
        .frame(width: 0, height: 0).opacity(0)
}
```

**TypeScript equivalent**

```tsx
// analogy: an invisible 0×0 button bound to the Escape key
<button
  onClick={cancel}
  style={{ width: 0, height: 0, opacity: 0 }}
  ref={el => registerShortcut("Escape", () => el?.click())}
/>
```

**Swift syntax:**
- `Button(action: cancel) { Color.clear }` — two-part button: `action:` is the handler, the trailing `{ ... }` is its label content (here an invisible clear color).
- `.keyboardShortcut(.escape, modifiers: [])` — binds a key with no modifiers; `[]` is an empty modifier set. TS: a global key listener.

This is an invisible 0×0 button wired to the Escape key — a common SwiftUI trick to grab a keystroke. `commit()` calls `onCommit(draft)`; `cancel()` calls `onCancel()`.

## How it connects

It edits a text `SlideElement`'s text — but only indirectly. The parent (the slide editor/canvas) decides which element is being edited, supplies `initialText` and the matching `font`/`color`/`alignment`/`frame`, and provides `onCommit`/`onCancel`. The parent's `onCommit` writes `draft` into the element through the `ModelContext` so it's undoable, which is also what flags `Slide.isManuallyEdited` and re-arms `LiveState`.

## Gotchas / why it matters

- **The overlay never mutates the model.** Keeping the edit in local `draft` and committing through a callback is what makes Cmd-Z a single clean step and keeps undo centralized. Don't "shortcut" by writing `element.text` from here.
- Escape needs the hidden-button hack because `TextEditor` swallows it; if you replace the editor control, re-verify Escape still cancels.
- The transparent shield (`opacity(0.001)` + `contentShape`) is intentional — it both blocks the canvas and makes a click-away commit. A fully clear color wouldn't reliably hit-test.
