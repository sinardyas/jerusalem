# `SlideNavigatorView.swift`

> The editor's left-rail slide picker: a `+`-to-add list of the item's slides, each shown as a numbered thumbnail with its section label, two-way bound to the currently-edited slide.

**Location:** `Sources/Jerusalem/Editor/SlideNavigatorView.swift`
**Role:** SwiftUI view

## What it does (plain English)

This is the little vertical list of slides on the left side of the editor. It shows every slide in the parent item, in order, as a row: a number, a small live thumbnail of the slide, and its section label (or "Slide N"). An "Edited" badge appears under any slide that's been hand-edited.

Selecting a row changes which slide the whole editor is designing, because the list's selection is **two-way bound** to the editor's `slideID`. There's a `+` button in the header that adds a fresh blank slide via a callback the parent provides.

Each thumbnail is rendered by the **shared renderer** (`RenderableSlideView`), so the picker always matches exactly what's on the canvas and what the audience would see — no separate preview code path.

## Swift you'll meet in this file

- `struct SlideNavigatorView: View { var body: some View }` — SwiftUI view ≈ React component; `body` ≈ returned JSX, `some View` = opaque return type.
- `@Bindable var item: Item` — bind to the SwiftData `@Model`; `@Binding var selection: PersistentIdentifier?` — two-way selection prop (`[value, setValue]` from the parent).
- `var onAddSlide: () -> Void` — a callback prop (a function with no args/result, like `onClick`).
- `List(selection: $selection) { … }.listStyle(.sidebar)` — a native selectable list styled as a sidebar; `$selection` makes clicks update the parent's state (`$` = the binding form of the prop).
- `ForEach(Array(item.orderedSlides.enumerated()), id: \.element.persistentModelID) { index, slide in … }` — `.map` with an index; `.enumerated()` pairs each slide with its position; `id:` gives a stable React-style key.
- `.tag(slide.persistentModelID as PersistentIdentifier?)` — tags a row with the value selecting it sets into `$selection`.
- `Image(systemName: "plus")` — an SF Symbol icon; `.help("…")` — a tooltip; `.buttonStyle(.borderless)` — flat button.
- `RenderableSlideView(renderable: RenderableSlide(slide))` — the shared renderer drawing a value-type snapshot of the slide.
- `slide.sectionLabel ?? "Slide \(index + 1)"` — `??` nullish fallback + `\( )` string interpolation; `if slide.isManuallyEdited { … }` — conditional view.

## Code walkthrough

### `body` — header + selectable list

```swift
var body: some View {
    VStack(spacing: 0) {
        header
        Divider()
        List(selection: $selection) {
            ForEach(Array(item.orderedSlides.enumerated()), id: \.element.persistentModelID) { index, slide in
                NavigatorRow(index: index, slide: slide)
                    .tag(slide.persistentModelID as PersistentIdentifier?)
            }
        }
        .listStyle(.sidebar)
    }
    .background(Color(nsColor: .windowBackgroundColor))
}
```

**TypeScript equivalent**

```tsx
// @Bindable item → item prop; @Binding selection → [selection, setSelection] pair
function SlideNavigatorView({
  item,
  selection,
  setSelection,
  onAddSlide,
}: {
  item: Item;
  selection: PersistentID | null;
  setSelection: (id: PersistentID | null) => void;
  onAddSlide: () => void;
}) {
  return (
    <Column spacing={0} style={{ background: "var(--window-bg)" }}>
      {header}
      <Divider />
      {/* analogy: List(selection:) → a selectable list; clicking a row calls setSelection */}
      <List selectedId={selection} onSelect={setSelection} style="sidebar">
        {/* .enumerated() gives [index, slide]; id:= stable React key */}
        {item.orderedSlides.map((slide, index) => (
          <NavigatorRow
            key={slide.persistentModelID}   // analogy: id: \.element.persistentModelID
            index={index}
            slide={slide}
            tag={slide.persistentModelID}    // analogy: .tag(...) — value selecting this row sets
          />
        ))}
      </List>
    </Column>
  );
}
```

**Swift syntax:**
- `struct SlideNavigatorView: View` — `struct … : View` declares a value-type that conforms to the `View` protocol; it's the unit SwiftUI renders. TS analog: a function component.
- `var body: some View` — the rendered content; `some View` is an opaque return type. TS analog: the JSX a component returns.
- `@Bindable var item` / `@Binding var selection` — `@Bindable` makes a SwiftData model two-way-bindable; `@Binding` is a two-way prop owned by the parent. `$selection` is the binding *handle* you pass to controls. TS analog: `item` prop + a `[value, setValue]` pair.
- `List(selection: $selection) { ForEach(…) { … } }` — `ForEach` is `.map` to views; the **trailing closure** `{ index, slide in … }` is the body (`in` separates params from body). TS analog: `array.map((slide, index) => …)`.
- `id: \.element.persistentModelID` — `\.element.persistentModelID` is a **key path** (a typed pointer reaching into each tuple's `.element`, then its id) used as the stable list key.
- `.tag(slide.persistentModelID as PersistentIdentifier?)` — `as PersistentIdentifier?` is an **upcast to optional** so the tag's type matches `selection`'s `PersistentIdentifier?`.

The `List(selection: $selection)` is the key piece: it binds the *list's* current selection to the editor's `slideID`. Each row is `.tag`ged with that slide's `persistentModelID`, so clicking a row writes that id into `$selection` — and because the parent uses the same binding, the canvas/inspector immediately switch to the chosen slide. `enumerated()` gives the `index` for the row number; `id: \.element.persistentModelID` keeps SwiftUI's diffing stable across reorders.

### `header` — the title + add button

```swift
private var header: some View {
    HStack(spacing: 6) {
        Text("Slides").font(.headline)
        Spacer()
        Button(action: onAddSlide) { Image(systemName: "plus") }
            .help("Add a blank slide")
            .buttonStyle(.borderless)
    }
    .padding(.horizontal, 12).padding(.vertical, 10)
}
```

**TypeScript equivalent**

```tsx
const header = (
  <Row spacing={6} style={{ padding: "10px 12px" }}>
    <span className="headline">Slides</span>
    <Spacer /> {/* analogy: flex spacer pushes the button to the right */}
    <button onClick={onAddSlide} title="Add a blank slide" className="borderless">
      <Icon name="plus" /> {/* analogy: Image(systemName: "plus") */}
    </button>
  </Row>
);
```

**Swift syntax:**
- `private var header: some View` — a **computed view property**: a piece of `body` extracted into its own named getter. TS analog: a `const header = <…>` (or a small sub-component).
- `Button(action: onAddSlide) { … }` — `action:` is the click handler, the trailing closure is the label. TS analog: `<button onClick={onAddSlide}>…</button>`.
- `Spacer()` — a flexible gap that pushes siblings apart. TS analog: a flex spacer / `margin-left: auto`.

A "Slides" title, a flex `Spacer`, and a borderless `+` button that just calls the parent's `onAddSlide` (the navigator doesn't create slides itself — the editor owns that, because it knows the theme/order rules).

### `NavigatorRow` — number, thumbnail, label, badge

```swift
private struct NavigatorRow: View {
    let index: Int
    let slide: Slide
    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)").font(.caption.monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 18, alignment: .trailing)
            RenderableSlideView(renderable: RenderableSlide(slide))
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(slide.sectionLabel ?? "Slide \(index + 1)").font(.callout).lineLimit(1)
                if slide.isManuallyEdited {
                    Text("Edited").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
```

**TypeScript equivalent**

```tsx
function NavigatorRow({ index, slide }: { index: number; slide: Slide }) {
  return (
    <Row spacing={10} style={{ paddingTop: 4, paddingBottom: 4 }}>
      {/* 1-based number, right-aligned, tabular digits */}
      <span
        className="caption"
        style={{ fontVariantNumeric: "tabular-nums", width: 18, textAlign: "right", opacity: 0.6 }}
      >
        {index + 1}
      </span>

      {/* analogy: shared renderer drawing a snapshot of the slide */}
      <RenderableSlideView
        renderable={new RenderableSlide(slide)}
        style={{ width: 96, height: 54, borderRadius: 4, border: "1px solid rgba(128,128,128,0.3)" }}
      />

      <Column alignment="leading" spacing={2}>
        {/* ?? nullish fallback */}
        <span className="callout" style={{ /* lineLimit(1) */ whiteSpace: "nowrap", overflow: "hidden" }}>
          {slide.sectionLabel ?? `Slide ${index + 1}`}
        </span>
        {/* if slide.isManuallyEdited → conditionally render the badge */}
        {slide.isManuallyEdited && (
          <span className="caption2" style={{ opacity: 0.6 }}>
            Edited
          </span>
        )}
      </Column>

      <Spacer minLength={0} />
    </Row>
  );
}
```

**Swift syntax:**
- `let index: Int` / `let slide: Slide` — `let` props are immutable inputs (the row never reassigns them). TS analog: plain props.
- `Text(slide.sectionLabel ?? "Slide \(index + 1)")` — `??` is the nullish-coalescing operator (`sectionLabel ?? fallback`); `\(index + 1)` interpolates. TS analog: `slide.sectionLabel ?? \`Slide ${index + 1}\``.
- `if slide.isManuallyEdited { Text("Edited") … }` — an `if` **inside a view builder** conditionally includes the child. TS analog: `{cond && <…/>}`.
- `Spacer(minLength: 0)` — a flexible trailing gap. TS analog: flex spacer.

Each row is a horizontal stack: a right-aligned 1-based number, a 96×54 thumbnail rendered by `RenderableSlideView` (clipped to a rounded rect with a hairline border), and a label that falls back to "Slide N". When `slide.isManuallyEdited` is true, an "Edited" sub-label appears — the same flag `ContentRebuilder` checks, surfaced here so the operator can see at a glance which slides won't be auto-regenerated.

## How it connects

- **Parent (`SlideEditorView`):** instantiates this with `item`, `$slideID` (as `selection`), and `onAddSlide: addBlankSlide`. Picking a row drives the canvas + inspector to that slide; the `+` button runs the editor's blank-slide insertion.
- **Shared renderer:** thumbnails use `RenderableSlideView`/`RenderableSlide` — the same path as the canvas base layer and the audience output, so the picker can never drift from reality.
- **`isManuallyEdited`:** read-only here (badge display); it's *set* by the canvas/inspector and consulted by `ContentRebuilder`.

## Gotchas / why it matters

- **Selection is the editor's `slideID`, not local state.** The two-way `$selection` binding is what makes clicking a row change the whole editor. Keep `.tag(...)` matching the binding's type (`PersistentIdentifier?`) or selection silently stops working.
- **Stable list identity.** `id: \.element.persistentModelID` (not the index) keeps thumbnails and selection correct when slides are reordered or inserted.
- **No second render path.** Thumbnails reuse the shared renderer on purpose — don't add a separate mini-renderer; that would risk the picker disagreeing with the live output.
- **Adding slides is delegated.** The navigator calls back rather than inserting models itself, so theming/order stay centralized in the editor.
