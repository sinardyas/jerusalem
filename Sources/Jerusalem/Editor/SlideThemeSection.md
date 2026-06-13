# `SlideThemeSection.swift`

> The inspector's "Theme" section: shows a preview swatch and the theme name, a (stubbed) Change… picker, and a "Set as default style for new slides" button that copies the selected text element's typography into the item's theme.

**Location:** `Sources/Jerusalem/Editor/SlideThemeSection.swift`
**Role:** SwiftUI view (plus reusable `ThemePreviewSwatch` and a `ThemePickerSheet`)

## What it does (plain English)

A theme is the item-wide default look (background color, font, text color, bold) used when new slides are created. This section displays the current theme as a small "Aa" preview swatch with its name, offers a "Change…" button (which opens a picker sheet — currently just the one bundled "Default Dark" theme, since a full theme library is a later phase), and a primary action that pushes the *currently selected text element's* styling back into the theme so future slides inherit it.

That last button is the real edit here: "Set as default style for new slides" takes whatever font/size/color the selected text box has and copies it onto `item.theme`. It's disabled unless a text element is selected, because there's nothing meaningful to copy from an image or shape.

## Swift you'll meet in this file

- `@Bindable var item: Item` — the SwiftData item whose `theme` is read and updated.
- `var selectedElement: SlideElement?` — `SlideElement | null`; the optional selected object (may be nothing).
- `var onChange: () -> Void` — parent callback after an edit.
- `@State private var showThemePicker = false` — local boolean state (`const [showThemePicker, setShowThemePicker] = useState(false)`) controlling the sheet.
- A computed `var theme: Theme { ... }` with **lazy creation**: if `item.theme` is nil it makes a default, assigns it, and returns it. (`if let existing = item.theme { return existing }` unwraps an optional.) TS analog: a getter that lazily materializes and caches.
- Controls: `Button("Change…") { ... }` = a button; `.buttonStyle(.link)` / `.borderless` = link/flat styling; `Label(_, systemImage:)` = text + icon; `.disabled(...)` = greys out the control (`disabled` attr); `.sheet(isPresented:)` = a modal presented when a bool is true.
- `@Environment(\.dismiss) private var dismiss` — pulls the "close this sheet" action from context (React-Context-like injection). TS analog: `const dismiss = useContext(DismissContext)`.
- `ZStack` = layered children (`<Layered>`); `.font(.custom(name, size:).weight(...))` = a named font; `Color(hex:)` builds a color from a hex string.

## Code walkthrough

### The lazy `theme` accessor

```swift
private var theme: Theme {
    if let existing = item.theme { return existing }
    let fresh = Theme.makeDefault()
    item.theme = fresh
    return fresh
}
```

**TypeScript equivalent**

```ts
get theme(): Theme {
  if (item.theme != null) return item.theme;   // analogy: if let existing = item.theme
  const fresh = Theme.makeDefault();
  item.theme = fresh;                          // side effect: materialize on first read
  return fresh;
}
```

**Swift syntax:**
- `private var theme: Theme { ... }` — a computed (read-only) property; recomputed each access, no stored backing. TS analog: a `get` accessor.
- `if let existing = item.theme { return existing }` — optional binding: enter the block (with `existing` unwrapped) only when `item.theme` is non-nil. TS: `if (item.theme != null) return item.theme;`.

Reading `theme` guarantees the item *has* one — it materializes and assigns a default on first access. Useful because the rest of the view can treat `theme` as non-optional.

### The section body

```swift
InspectorSection(title: "Theme") {
    HStack(alignment: .center, spacing: 10) {
        ThemePreviewSwatch(theme: theme).frame(width: 80, height: 45)
        VStack(alignment: .leading, spacing: 2) {
            Text(theme.name).font(.callout)
            Button("Change…") { showThemePicker = true }.buttonStyle(.link)
        }
        Spacer()
    }
    Button {
        guard let element = selectedElement, element.kind == .text else { return }
        theme.copy(from: element)
        onChange()
    } label: {
        Label("Set as default style for new slides", systemImage: "wand.and.stars")
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.borderless)
    .disabled(selectedElement?.kind != .text)
}
.sheet(isPresented: $showThemePicker) {
    ThemePickerSheet(currentTheme: theme, onPick: { _ in showThemePicker = false })
}
```

**TypeScript equivalent**

```tsx
<InspectorSection title="Theme">
  <Row align="center" style={{ gap: 10 }}>
    <ThemePreviewSwatch theme={theme} style={{ width: 80, height: 45 }} />
    <Column align="start" style={{ gap: 2 }}>
      <Text>{theme.name}</Text>
      <button className="link" onClick={() => setShowThemePicker(true)}>Change…</button>
    </Column>
    <Spacer />
  </Row>

  <button
    className="borderless"
    disabled={selectedElement?.kind !== "text"}   // analogy: .disabled(...) + optional chaining
    onClick={() => {
      if (selectedElement == null || selectedElement.kind !== "text") return; // analogy: guard
      theme.copy(selectedElement);
      onChange();
    }}
  >
    {/* analogy: Label = text + icon */}
    <Label icon="wand.and.stars">Set as default style for new slides</Label>
  </button>

  {/* analogy: .sheet(isPresented:) = modal shown when the bool is true */}
  {showThemePicker && (
    <ThemePickerSheet currentTheme={theme} onPick={() => setShowThemePicker(false)} />
  )}
</InspectorSection>
```

**Swift syntax:**
- `Button { action } label: { ... }` — two-trailing-closure button: first `{ }` is the tap handler, `label:` is the visible content. TS: `onClick` + children.
- `guard let element = selectedElement, element.kind == .text else { return }` — bind `element` *and* require `.kind == .text`, else bail. TS: a combined early-return `if`.
- `.disabled(selectedElement?.kind != .text)` — `selectedElement?.kind` is optional chaining: nil selection → `nil`, which is `!= .text`, so disabled. TS: `selectedElement?.kind !== "text"`.
- `.sheet(isPresented: $showThemePicker) { ... }` — presents the closure's view modally while the bound bool is true.
- `onPick: { _ in showThemePicker = false }` — `_` ignores the closure's argument. TS: `() => setShowThemePicker(false)`.

The top row is the swatch + name + "Change…" (which just flips `showThemePicker`). The primary button guards that a **text** element is selected (`guard let element = selectedElement, element.kind == .text`), then calls `theme.copy(from: element)` to absorb its typography and fires `onChange()`. `.disabled(selectedElement?.kind != .text)` greys it out otherwise — note `selectedElement?.kind` uses optional chaining so a nil selection is also "not text." The `.sheet` presents `ThemePickerSheet` modally when the bool is true.

### `ThemePreviewSwatch`

A reusable mini-render of the theme: its background color with an "Aa" in its font/color:

```swift
ZStack {
    Color(hex: theme.backgroundColorHex)
    Text("Aa")
        .font(.custom(theme.fontName, size: 20).weight(theme.isBold ? .bold : .regular))
        .foregroundStyle(Color(hex: theme.textColorHex))
}
.clipShape(RoundedRectangle(cornerRadius: 4))
```

**TypeScript equivalent**

```tsx
<Layered style={{ borderRadius: 4, overflow: "hidden" }}> {/* analogy: ZStack + .clipShape */}
  <div style={{ position: "absolute", inset: 0, background: Color.fromHex(theme.backgroundColorHex) }} />
  <Text
    style={{
      fontFamily: theme.fontName, fontSize: 20,          // analogy: .font(.custom(name, size:))
      fontWeight: theme.isBold ? 700 : 400,              // analogy: .weight(.bold : .regular)
      color: Color.fromHex(theme.textColorHex),
    }}
  >
    Aa
  </Text>
</Layered>
```

**Swift syntax:**
- `.font(.custom(theme.fontName, size: 20).weight(...))` — builds a named font at a size, then adjusts weight by chaining `.weight(...)`. TS: `fontFamily` + `fontSize` + `fontWeight`.
- `theme.isBold ? .bold : .regular` — ternary choosing a `Font.Weight`. TS: `700 : 400`.
- `.clipShape(RoundedRectangle(cornerRadius: 4))` — clips children to a rounded rect. TS: `borderRadius` + `overflow: hidden`.

### `ThemePickerSheet`

A placeholder picker — for the MVP it only ships the bundled default, so it renders a single selected row, a "More themes ship in a future update." note, and a Close button. `@Environment(\.dismiss)` provides `dismiss()` for the Close button; `.keyboardShortcut(.defaultAction)` makes it the Enter-key default.

```swift
HStack {
    Spacer()
    Button("Close") { dismiss() }
        .keyboardShortcut(.defaultAction)
}
```

**TypeScript equivalent**

```tsx
<Row>
  <Spacer />
  <button
    onClick={() => dismiss()}              // analogy: @Environment(\.dismiss) → dismiss()
    data-default-action                    // analogy: .keyboardShortcut(.defaultAction) (Enter)
  >
    Close
  </button>
</Row>
```

**Swift syntax:**
- `@Environment(\.dismiss) private var dismiss` — reads the built-in dismiss action from the environment; calling `dismiss()` closes the sheet. TS analog: `const dismiss = useContext(DismissContext)`.
- `.keyboardShortcut(.defaultAction)` — marks this button as the default (Enter) action.

## How it connects

It edits the `Item`'s `theme` (a SwiftData `Theme` model) — specifically by copying a selected text `SlideElement`'s typography into it. The parent inspector hosts it under the "Slide" tab and provides `item`, the optional `selectedElement`, and `onChange`. Because `theme` drives the default look of *future* slides (and the preview swatch), this is item-wide design state, not per-element. `onChange()` persists via `ModelContext` (undoable) and re-renders.

## Gotchas / why it matters

- **The default button only works on text elements** (`guard ... element.kind == .text`) and is disabled otherwise — copying typography from an image/shape is meaningless. Keep both the guard *and* the `.disabled` in sync.
- The lazy `theme` getter mutates the model (`item.theme = fresh`) as a side effect of reading — fine here, but be aware that merely rendering the section can create the theme on a brand-new item.
- The picker is intentionally a stub for the MVP; a real theme library is a later phase. Don't treat the single-row sheet as a bug.
- Theme colors are stored as hex strings (`backgroundColorHex`, `textColorHex`) and rendered via `Color(hex:)`, consistent with the background section — same hex-as-source-of-truth convention.
