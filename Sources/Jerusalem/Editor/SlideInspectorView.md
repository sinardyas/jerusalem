# `SlideInspectorView.swift`

> The right-hand inspector panel: a tabbed container (Format / Arrange / Slide) that hosts per-element styling controls and slide-wide settings, where every edit two-way-binds a SwiftData model property and flips `isManuallyEdited`.

**Location:** `Sources/Jerusalem/Editor/SlideInspectorView.swift`
**Role:** SwiftUI view

## What it does (plain English)

This is the properties panel on the right. It's split into **three tabs**:

- **Format** — the selected object's styling. For text: Font, Paragraph, and Stroke & Shadow sections. For shapes: shape type, fill, corner radius, outline. For images: the filename + a Replace button.
- **Arrange** — the selected object's position/size + layer order (delegated to `SlideArrangeSection`).
- **Slide** — slide-wide settings: a label, the background, and the theme.

It's mostly a *router*: pick a tab, and based on whether an element is selected and what `kind` it is, show the right sub-inspector. A nice touch — selecting an object on the canvas auto-switches the panel to **Format**, and deselecting returns it to **Slide**, so you never have to hunt for the relevant controls.

The real pattern to notice is how every control writes back. The styling sub-views (`TextElementInspector`, `ShapeElementInspector`, `ImageElementInspector`) each build their bindings through a small `edited(\.keyPath)` helper that, on *set*, writes the model property **and** calls `onChange()` — which marks `slide.isManuallyEdited = true`. So changing a font size both updates the live model (instantly reflected by the shared renderer) and tells `ContentRebuilder` to leave this hand-edited slide alone.

## Swift you'll meet in this file

- `@Bindable var item: Item` / `@Bindable var slide: Slide` — bind to SwiftData `@Model`s; `var selectedElement: SlideElement?` — optional selected element (`T | null`).
- `@State private var tab: InspectorTab = .slide` — `useState` for the current tab.
- `Picker("", selection: $tab) { ForEach(InspectorTab.allCases) { … } }.pickerStyle(.segmented)` — a segmented control bound to state.
- `ScrollView { VStack(alignment: .leading) { switch tab { … } } }` — scroll + vertical stack; `switch` chooses which sub-view to show.
- `@ViewBuilder private var formatTab: some View` — a computed view property that can contain `if`/`switch`.
- `.onChange(of: selectedElement?.persistentModelID) { _, id in … }` — run an effect when the selected element's id changes (auto-switch tab).
- **Key paths:** `edited(\.fontName)`, `colorBinding(\.colorHex)` — `\.foo` is a key path (a typed pointer to a property); `ReferenceWritableKeyPath<SlideElement, T>` lets a generic helper get/set any field.
- `Binding(get: { … }, set: { … })` — a **custom two-way binding** with side effects on set (this is the workhorse here).
- `Toggle("B", isOn: edited(\.isBold)).toggleStyle(.button)` / `Slider(value:in:step:)` / `ColorPicker("", selection:)` / `Stepper(…, in: 8...400, step: 1)` — native macOS controls.
- `Color(hex: …)` / `$0.hexString` — convert between a stored hex string and a SwiftUI `Color`.
- `private struct TextElementInspector: View` — file-private nested view; `enum ShapeType`/`TextAlignmentOption` — model enums used as `.tag(...)` values in pickers.
- `NSOpenPanel`, `MediaStorage.importFile(at:)`, `NSSound.beep()` — AppKit file picker + import + error beep.

## Code walkthrough

### `body` — header chip, tab picker, routed content

```swift
VStack(spacing: 0) {
    InspectorHeaderChip(kind: selectedElement?.kind)
    Picker("", selection: $tab) {
        ForEach(InspectorTab.allCases) { Text($0.title).tag($0) }
    }
    .pickerStyle(.segmented).labelsHidden()
    Divider()
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            switch tab {
            case .format:  formatTab
            case .arrange: arrangeTab
            case .slide:   slideTab
            }
        }
    }
}
.onChange(of: selectedElement?.persistentModelID) { _, id in
    tab = InspectorTab.onSelectionChange(hasSelection: id != nil)
}
```

A header chip showing the selected kind, a segmented tab picker, then a scroll view that `switch`es to one of three tab bodies. The `.onChange` is the auto-focus: whenever the selected element's id changes, `InspectorTab.onSelectionChange` decides the tab (Format if something is selected, Slide if not).

### The three tab bodies

```swift
@ViewBuilder private var formatTab: some View {
    if let element = selectedElement {
        switch element.kind {
        case .text:  TextElementInspector(element: element, onChange: markEdited)
        case .shape: ShapeElementInspector(element: element, onChange: markEdited)
        case .image: ImageElementInspector(element: element, onChange: markEdited)
        }
    } else {
        InspectorSection(title: "Format") { Text("Select an object on the canvas to edit its style.") … }
    }
}
```

`formatTab` dispatches by element `kind`; `arrangeTab` shows `SlideArrangeSection` (or a hint); `slideTab` always shows the slide label field plus `SlideBackgroundSection` and `SlideThemeSection`. Every sub-view receives `onChange: markEdited`, and:

```swift
private func markEdited() { slide.isManuallyEdited = true }
```

### The binding helpers — where edits become model writes (the key pattern)

Inside `TextElementInspector` (and mirrored in the shape/image inspectors):

```swift
/// Binding to a model property that fires `onChange` (marks the slide edited).
private func edited<T>(_ keyPath: ReferenceWritableKeyPath<SlideElement, T>) -> Binding<T> {
    Binding(get: { element[keyPath: keyPath] },
            set: { element[keyPath: keyPath] = $0; onChange() })
}
private func colorBinding(_ keyPath: ReferenceWritableKeyPath<SlideElement, String>) -> Binding<Color> {
    Binding(get: { Color(hex: element[keyPath: keyPath]) },
            set: { element[keyPath: keyPath] = $0.hexString; onChange() })
}
private var fontSizeBinding: Binding<Double> {
    Binding(get: { element.fontSize },
            set: { element.fontSize = min(400, max(8, $0)); onChange() })
}
```

This is the heart of the file. `edited(\.someProp)` produces a `Binding` that, on *set*, writes the model property **and** calls `onChange()` (→ marks the slide edited). Because it's generic over a `ReferenceWritableKeyPath`, one helper covers every field — `edited(\.fontName)`, `edited(\.isBold)`, `edited(\.alignment)`, etc. `colorBinding` adds hex↔`Color` translation on both ends; `fontSizeBinding` adds a `min(400, max(8, …))` clamp so a typed value can't break layout.

### Text sections

```swift
private var fontSection: some View {
    InspectorSection(title: "Font") {
        InspectorRow(label: "Family") {
            Picker("", selection: edited(\.fontName)) {
                ForEach(Self.fontChoices, id: \.self) { Text($0).tag($0) }
            }.labelsHidden()
        }
        InspectorRow(label: "Size") {
            HStack(spacing: 8) {
                TextField("", value: fontSizeBinding, format: .number)…
                Stepper("", value: fontSizeBinding, in: 8...400, step: 1)…
                ColorPicker("", selection: colorBinding(\.colorHex)).labelsHidden()
            }
        }
        InspectorRow(label: "Style") {
            HStack(spacing: 6) {
                Toggle("B", isOn: edited(\.isBold)).font(.body.bold())
                Toggle("I", isOn: edited(\.isItalic)).font(.body.italic())
                Toggle("U", isOn: edited(\.isUnderlined)).underline(element.isUnderlined)
            }.toggleStyle(.button)
        }
    }
}
```

Font family picker, a size field + stepper (sharing `fontSizeBinding` so they stay in sync), a text-color picker, and the bold/italic/underline toggles. `paragraphSection` adds alignment (a segmented picker of SF Symbols tagged with `TextAlignmentOption` cases), line/letter-spacing sliders (via a `sliderRow` helper that shows a formatted value), and an Auto-fit switch. `strokeShadowSection` has outline on/off + color + width, and shadow on/off + color + blur + offset — with the color/slider controls `.disabled(!element.hasStroke)` / `!element.hasShadow` so they grey out when the feature is off.

### Shape and image inspectors

`ShapeElementInspector` offers a shape-type segmented picker (rectangle/ellipse/rounded), a fill color, a corner-radius slider (disabled unless `shapeType == .roundedRectangle`), and an outline section — all through the same `edited`/`colorBinding` helpers.

`ImageElementInspector` shows the current filename (if any) and a Replace button:

```swift
private func pickImage() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false; …
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { element.imageFilename = try MediaStorage.importFile(at: url); onChange() }
    catch { NSSound.beep() }
}
```

It opens a native file picker, imports the file into app storage via `MediaStorage`, writes `imageFilename`, and `onChange()`s — beeping on failure.

## How it connects

- **From `SlideEditorView`:** receives `item`, `slide`, and `selectedElement`. The editor owns the actual `selection` state; the inspector just reacts to which element it is.
- **Per-kind dispatch:** `formatTab` routes by `element.kind` to the text/shape/image sub-inspectors; `arrangeTab` hands off to `SlideArrangeSection`; `slideTab` to `SlideBackgroundSection`/`SlideThemeSection`.
- **Writes the live model:** every binding mutates the `@Model` directly, so the shared renderer updates the canvas, the navigator thumbnail, and the inspector preview together. Those writes are also tracked by the editor's `UndoManager`, so ⌘Z reverts inspector edits.
- **`onChange → markEdited`:** the single thread tying every control to `slide.isManuallyEdited`.

## Gotchas / why it matters

- **Every edit must flip `isManuallyEdited`.** That's why all bindings go through `edited`/`colorBinding` (which call `onChange`) instead of `$element.field` directly — a binding that skipped `onChange` would let `ContentRebuilder` silently overwrite the operator's styling.
- **Clamp typed input.** `fontSizeBinding` pins to 8…400; an unclamped field could produce a font that breaks layout — bad on a Sunday morning.
- **Colors are stored as hex strings.** The UI works in `Color`; `colorBinding` translates both directions (`Color(hex:)` / `.hexString`). Don't store a `Color` on the model.
- **Live model editing, snapshot-protected output.** Inspector changes show instantly in the editor's previews but don't touch the audience screen until the operator re-arms (the `LiveState` snapshot rule).
- **Disabled controls are intentional.** Stroke/shadow/corner controls grey out when their feature is off — keep that wiring when adding fields.
