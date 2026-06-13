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

- `struct SlideInspectorView: View { var body: some View }` — SwiftUI view ≈ React component; `some View` = opaque return type.
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
- `private func edited<T>(_ keyPath:) -> Binding<T>` — a **generic** helper (`<T>` = type parameter); `8...400` = an inclusive range.
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

**TypeScript equivalent**

```tsx
function SlideInspectorView({
  item,
  slide,
  selectedElement,
}: {
  item: Item;
  slide: Slide;
  selectedElement: SlideElement | null;
}) {
  const [tab, setTab] = useState<InspectorTab>("slide");

  // .onChange(of: selectedElement?.persistentModelID) → effect on the selected id
  useEffect(() => {
    setTab(InspectorTab.onSelectionChange(selectedElement != null));
  }, [selectedElement?.persistentModelID]);

  return (
    <Column spacing={0}>
      <InspectorHeaderChip kind={selectedElement?.kind} />     {/* ?. → undefined if none */}
      {/* segmented Picker bound to [tab, setTab] */}
      <SegmentedPicker value={tab} onChange={setTab}>
        {InspectorTab.allCases.map((t) => (
          <Segment key={t} value={t}>{t.title}</Segment>       // .tag($0)
        ))}
      </SegmentedPicker>
      <Divider />
      <ScrollView>
        <Column alignment="leading" spacing={0}>
          {/* switch tab → choose the sub-view */}
          {tab === "format" ? formatTab : tab === "arrange" ? arrangeTab : slideTab}
        </Column>
      </ScrollView>
    </Column>
  );
}
```

**Swift syntax:**
- `@Bindable var item: Item` / `@Bindable var slide: Slide` — two-way model bindings; `var selectedElement: SlideElement?` is an optional prop. TS analog: model props + a `… | null` prop.
- `@State private var tab: InspectorTab = .slide` — local state initialized to the `.slide` case. TS analog: `useState("slide")`.
- `Picker("", selection: $tab) { ForEach(InspectorTab.allCases) { Text($0.title).tag($0) } }` — a control bound to `$tab`; each option `.tag($0)`s the value selecting it sets. `$0` is the implicit closure arg. TS analog: a controlled `<SegmentedPicker value onChange>`.
- `switch tab { case .format: formatTab … }` — a `switch` inside a view builder picking which child to show. TS analog: a `?:` chain or `switch`.
- `.onChange(of: selectedElement?.persistentModelID) { _, id in … }` — effect when the (optional, via `?.`) id changes; `(_, id)` = `(old, new)`. TS analog: `useEffect(…, [selectedElement?.persistentModelID])`.

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

**TypeScript equivalent**

```tsx
const formatTab = (() => {
  const element = selectedElement;
  if (element) {                                  // if let element = selectedElement
    switch (element.kind) {                        // dispatch by element kind
      case "text":  return <TextElementInspector element={element} onChange={markEdited} />;
      case "shape": return <ShapeElementInspector element={element} onChange={markEdited} />;
      case "image": return <ImageElementInspector element={element} onChange={markEdited} />;
    }
  }
  return (
    <InspectorSection title="Format">
      <span className="callout secondary">Select an object on the canvas to edit its style.</span>
    </InspectorSection>
  );
})();

// onChange handler shared by every sub-inspector:
const markEdited = () => { slide.isManuallyEdited = true; };
```

**Swift syntax:**
- `@ViewBuilder private var formatTab: some View` — `@ViewBuilder` lets a computed view property contain `if`/`switch`/multiple children (normally a getter returns one expression). TS analog: an IIFE / sub-component returning JSX.
- `if let element = selectedElement { … } else { … }` — optional binding with a fallback view. TS analog: `if (element) { … } return fallback`.
- `switch element.kind { case .text: … }` — dispatch by enum case. TS analog: `switch (element.kind)`.
- `onChange: markEdited` — passing the function `markEdited` by reference (not calling it). TS analog: `onChange={markEdited}`.

`formatTab` dispatches by element `kind`; `arrangeTab` shows `SlideArrangeSection` (or a hint); `slideTab` always shows the slide label field plus `SlideBackgroundSection` and `SlideThemeSection`. Every sub-view receives `onChange: markEdited`, and:

```swift
private func markEdited() { slide.isManuallyEdited = true }
```

**TypeScript equivalent**

```ts
// Flip the slide's "a human touched this" flag so ContentRebuilder won't
// later overwrite it. Passed by reference as the onChange callback below.
function markEdited(): void {
  slide.isManuallyEdited = true;
}
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

**TypeScript equivalent**

```ts
// A SwiftUI Binding ≈ a { get, set } pair (a controlled-value adapter).
// edited(\.field) → a generic helper producing a binding that ALSO fires onChange on set.
function edited<K extends keyof SlideElement>(key: K) {
  return {
    get: () => element[key],
    set: (v: SlideElement[K]) => {
      element[key] = v;          // write the model property…
      onChange();                // …and mark the slide edited
    },
  };
}

// hex-string field exposed as a Color (translate both directions)
function colorBinding(key: "colorHex" | "strokeColorHex" | "shadowColorHex" | "fillColorHex") {
  return {
    get: () => Color.fromHex(element[key]),
    set: (c: Color) => { element[key] = c.hexString; onChange(); },
  };
}

// font size, clamped so a typed value can't break layout
const fontSizeBinding = {
  get: () => element.fontSize,
  set: (v: number) => { element.fontSize = Math.min(400, Math.max(8, v)); onChange(); },
};
```

**Swift syntax:**
- `private func edited<T>(_ keyPath: ReferenceWritableKeyPath<SlideElement, T>) -> Binding<T>` — a **generic** function (`<T>` = a type parameter inferred per call); `ReferenceWritableKeyPath<SlideElement, T>` names a settable property of any type `T`. One helper covers every field. TS analog: `edited<K extends keyof SlideElement>(key: K)`.
- `Binding(get: { … }, set: { … })` — a **custom two-way binding**: a getter/setter pair. The `set` closure runs side effects (`onChange()`). TS analog: a `{ get, set }` adapter.
- `element[keyPath: keyPath]` — read/write through a key path. TS analog: `element[key]`.
- `set: { element[keyPath: keyPath] = $0; onChange() }` — `$0` is the new value passed to the setter. TS analog: `set: (v) => { element[key] = v; onChange(); }`.
- `private var fontSizeBinding: Binding<Double>` — a computed property returning a binding; `min(400, max(8, $0))` clamps. TS analog: a `const` `{ get, set }` with `Math.min/max`.

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

**TypeScript equivalent**

```tsx
const fontSection = (
  <InspectorSection title="Font">
    <InspectorRow label="Family">
      {/* Picker bound to the edited(\.fontName) binding */}
      <Picker binding={edited("fontName")}>
        {TextElementInspector.fontChoices.map((f) => (
          <Option key={f} value={f}>{f}</Option>             // id: \.self → the string is its own key
        ))}
      </Picker>
    </InspectorRow>

    <InspectorRow label="Size">
      <Row spacing={8}>
        {/* TextField + Stepper SHARE fontSizeBinding so they stay in sync */}
        <NumberField binding={fontSizeBinding} width={50} />
        <Stepper binding={fontSizeBinding} min={8} max={400} step={1} />   // in: 8...400
        <ColorPicker binding={colorBinding("colorHex")} />
      </Row>
    </InspectorRow>

    <InspectorRow label="Style">
      <Row spacing={6} className="toggle-button-group">                   {/* .toggleStyle(.button) */}
        <Toggle label="B" binding={edited("isBold")} bold />
        <Toggle label="I" binding={edited("isItalic")} italic />
        <Toggle label="U" binding={edited("isUnderlined")} underline={element.isUnderlined} />
      </Row>
    </InspectorRow>
  </InspectorSection>
);
```

**Swift syntax:**
- `Picker("", selection: edited(\.fontName)) { … }` — the picker's selection is the binding from `edited`; `\.fontName` is a **key path** literal naming the property. TS analog: `<Picker binding={edited("fontName")}>`.
- `ForEach(Self.fontChoices, id: \.self) { Text($0).tag($0) }` — `id: \.self` uses each string *as its own* identity key; `$0` is the implicit element. TS analog: `arr.map(f => <Option key={f} value={f}>{f}</Option>)`.
- `Stepper("", value: fontSizeBinding, in: 8...400, step: 1)` — `in: 8...400` is an **inclusive range** bounding the stepper. TS analog: `min={8} max={400}`.
- `Toggle("B", isOn: edited(\.isBold))` — a toggle bound to a `Bool` binding. TS analog: `<Toggle binding={edited("isBold")} />`.

Font family picker, a size field + stepper (sharing `fontSizeBinding` so they stay in sync), a text-color picker, and the bold/italic/underline toggles. `paragraphSection` adds alignment (a segmented picker of SF Symbols tagged with `TextAlignmentOption` cases), line/letter-spacing sliders (via a `sliderRow` helper that shows a formatted value), and an Auto-fit switch. `strokeShadowSection` has outline on/off + color + width, and shadow on/off + color + blur + offset — with the color/slider controls `.disabled(!element.hasStroke)` / `!element.hasShadow` so they grey out when the feature is off.

The `sliderRow` helper (a label, a right-aligned value readout, and a `Slider`):

```swift
private func sliderRow(_ label: String, value: Binding<Double>,
                       range: ClosedRange<Double>, step: Double, display: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        HStack {
            Text(label).font(.callout)
            Spacer()
            Text(display).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        Slider(value: value, in: range, step: step)
    }
}
```

**TypeScript equivalent**

```tsx
function sliderRow(
  label: string,
  binding: { get(): number; set(v: number): void },
  range: { lower: number; upper: number },   // ClosedRange<Double>
  step: number,
  display: string,
) {
  return (
    <Column alignment="leading" spacing={3}>
      <Row>
        <span className="callout">{label}</span>
        <Spacer />                              {/* pushes the value to the right */}
        <span className="caption secondary" style={{ fontVariantNumeric: "tabular-nums" }}>
          {display}
        </span>
      </Row>
      <Slider binding={binding} min={range.lower} max={range.upper} step={step} />
    </Column>
  );
}
```

**Swift syntax:**
- `value: Binding<Double>` — accepts a binding as a parameter (controls drive it directly). TS analog: a `{ get, set }` param.
- `range: ClosedRange<Double>` — an inclusive range arg (`0.9...2.2`, etc.). TS analog: a `{ lower, upper }` pair.
- `Slider(value: value, in: range, step: step)` — binds the slider to the value, bounded by `range`. TS analog: `<Slider binding min max step />`.

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

**TypeScript equivalent**

```ts
async function pickImage() {
  // analogy: NSOpenPanel → a native file dialog
  const panel = new OpenPanel({ allowedContentTypes: ["image"], allowsMultipleSelection: false });

  // guard: user clicked OK AND a url exists, else bail
  if (panel.runModal() !== "ok" || panel.url == null) return;

  try {
    element.imageFilename = MediaStorage.importFile(panel.url); // copy into app storage
    onChange();
  } catch {
    Sound.beep();                                              // error feedback
  }
}
```

**Swift syntax:**
- `guard panel.runModal() == .OK, let url = panel.url else { return }` — guard combining a comparison and an optional binding (`url` must be non-nil); bail otherwise. TS analog: `if (panel.runModal() !== "ok" || panel.url == null) return`.
- `do { … try MediaStorage.importFile(at: url) … } catch { NSSound.beep() }` — `do`/`catch` error handling; `try` marks a throwing call. TS analog: `try { … } catch { … }`.
- `if let filename = element.imageFilename { … }` (in the body above) — show the row only when there's a filename. TS analog: `{element.imageFilename && <…/>}`.

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
