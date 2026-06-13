# `SlideBackgroundSection.swift`

> The inspector's "Background (slide)" section: pick the background kind (color / gradient / image / video) and edit only the controls relevant to that kind, including a swatch palette and file pickers.

**Location:** `Sources/Jerusalem/Editor/SlideBackgroundSection.swift`
**Role:** SwiftUI view (plus a small reusable `SwatchGrid` view)

## What it does (plain English)

This section sets the whole slide's background. A segmented control at the top chooses one of four kinds — Color, Gradient, Image, Video — and the controls below swap to match. Pick Color and you get a quick swatch palette plus a full color picker; pick Gradient and you get two colors and an angle stepper; pick Image or Video and you get a "Choose…" button (a native macOS file picker) plus a "Remove" button. Showing only the relevant controls keeps the operator from setting, say, a gradient angle the renderer would ignore.

Every change writes straight onto the `Slide` model fields (`backgroundKind`, `backgroundColorHex`, `gradientHex2`, `gradientAngle`, `backgroundImageFilename`, `backgroundVideoFilename`) and then calls `onChange()`. Image/video files are copied into the app's media store first via `MediaStorage.importFile`, and only the returned filename is stored.

## Swift you'll meet in this file

- `@Bindable var slide: Slide` — the SwiftData model being edited; field writes here are persisted. TS analog: a mutable model object whose writes save.
- `var onChange: () -> Void` — parent callback fired after each edit.
- `private static let palette: [String]` — a type-level constant array (shared by all instances); referenced as `Self.palette`. TS analog: a `static readonly` class field / module constant.
- `Binding(get:set:)` — custom two-way bindings that transform on read/write (e.g. enum ↔ picker tag, `Color` ↔ hex string). TS analog: an object with `get value()` / `set value()`.
- `@ViewBuilder private var colorControls: some View` — computed sub-views, one per kind, selected by a `switch`. TS analog: a function component per kind.
- `T?` optionals: `slide.backgroundImageFilename` is `String?`; `if let filename = ...` renders the file row only when set; `!= nil` gates the Remove button.
- `guard ... else { return }` — early-exit if a condition fails (e.g. the file panel was cancelled).
- `do { try ... } catch { ... }` — Swift error handling; `try` calls a throwing function, `catch` handles failure (`NSSound.beep()`). TS analog: `try { ... } catch { ... }`.
- Controls: `Picker(...).pickerStyle(.segmented)` = a segmented control (radio-button bar); `ColorPicker` = `<input type=color>`; `Stepper` = a +/- numeric stepper; `Button(role: .destructive)` = a red/destructive button; `LabeledContent` = a label-value pair row.
- `NSOpenPanel` — AppKit's native open-file dialog; `.runModal()` blocks until the user picks/cancels.
- `LazyVGrid(columns:)` + `GridItem(.flexible())` — a responsive grid (like CSS grid).

## Code walkthrough

The `body` is the kind picker plus a `switch` choosing which control block to show:

```swift
InspectorSection(title: "Background", trailing: "(slide)") {
    Picker("Type", selection: Binding(
        get: { slide.backgroundKind },
        set: { slide.backgroundKind = $0; onChange() })) {
        Text("Color").tag(SlideBackgroundKind.color)
        Text("Gradient").tag(SlideBackgroundKind.gradient)
        Text("Image").tag(SlideBackgroundKind.image)
        Text("Video").tag(SlideBackgroundKind.video)
    }
    .pickerStyle(.segmented)
    .labelsHidden()

    switch slide.backgroundKind {
    case .color:    colorControls
    case .gradient: gradientControls
    case .image:    imageControls
    case .video:    videoControls
    }
}
```

**TypeScript equivalent**

```tsx
<InspectorSection title="Background" trailing="(slide)">
  {/* analogy: Picker(.segmented) = a segmented radio bar */}
  <SegmentedControl
    value={slide.backgroundKind}
    onChange={v => { slide.backgroundKind = v; onChange(); }}
    options={[
      { label: "Color", value: "color" },      // analogy: .tag(...) pairs label ↔ value
      { label: "Gradient", value: "gradient" },
      { label: "Image", value: "image" },
      { label: "Video", value: "video" },
    ]}
  />
  {(() => {
    switch (slide.backgroundKind) {
      case "color":    return colorControls;
      case "gradient": return gradientControls;
      case "image":    return imageControls;
      case "video":    return videoControls;
    }
  })()}
</InspectorSection>
```

**Swift syntax:**
- `Picker("Type", selection: ...) { ...options... }` — the `selection:` is the bound value; the trailing `{ }` holds the option views. TS analog: `<select value onChange>` with `<option>`s.
- `set: { slide.backgroundKind = $0; onChange() }` — `$0` is the first (only) closure argument (the new value). TS analog: `v => { ... }`. `;` separates two statements in one closure.
- `.tag(SlideBackgroundKind.color)` — associates an option view with the enum value the picker should select. TS analog: `<option value="color">`.
- `switch slide.backgroundKind { case .color: colorControls ... }` — picks a sub-view by enum case; each branch is just a view expression.

The picker's custom binding writes the chosen enum back to `slide.backgroundKind` and calls `onChange()`. `.tag(...)` pairs each `Text` with its enum case (how `Picker` knows which option maps to which value). `.labelsHidden()` drops the "Type" label since the segments are self-explanatory.

### Color

```swift
SwatchGrid(palette: Self.palette,
           selected: slide.backgroundColorHex,
           onSelect: { hex in slide.backgroundColorHex = hex; onChange() })
ColorPicker("More…", selection: Binding(
    get: { Color(hex: slide.backgroundColorHex) },
    set: { slide.backgroundColorHex = $0.hexString; onChange() }))
```

**TypeScript equivalent**

```tsx
<SwatchGrid
  palette={SlideBackgroundSection.palette}        // analogy: Self.palette
  selected={slide.backgroundColorHex}
  onSelect={hex => { slide.backgroundColorHex = hex; onChange(); }}
/>
<ColorPicker
  label="More…"
  value={Color.fromHex(slide.backgroundColorHex)} // analogy: get → Color(hex:)
  onChange={c => { slide.backgroundColorHex = c.hexString; onChange(); }} // set → hexString
/>
```

**Swift syntax:**
- `onSelect: { hex in ... }` — a closure with a named parameter `hex` before `in`. TS analog: `hex => { ... }`.
- `Color(hex:)` / `$0.hexString` — model stores a hex `String`; the binding converts to/from `Color` on each read/write so the model never holds a `Color`.

The quick swatches write a hex string directly; the "More…" `ColorPicker` round-trips through `Color(hex:)` / `$0.hexString` so the model always stores a hex string, not a `Color`.

### Gradient

Two `ColorPicker`s (first color = `backgroundColorHex`, second = `gradientHex2`) and an angle `Stepper`:

```swift
Stepper(value: Binding(
    get: { Int(slide.gradientAngle.rounded()) },
    set: { slide.gradientAngle = Double($0); onChange() }),
        in: 0...359, step: 15) {
    LabeledContent("Angle", value: "\(Int(slide.gradientAngle.rounded()))°")
}
```

**TypeScript equivalent**

```tsx
<Stepper
  value={Math.round(slide.gradientAngle)}                 // analogy: get → Int(rounded)
  onChange={v => { slide.gradientAngle = v; onChange(); }} // analogy: set → Double($0)
  min={0} max={359} step={15}
>
  {/* analogy: LabeledContent = label-value row */}
  <LabeledContent label="Angle" value={`${Math.round(slide.gradientAngle)}°`} />
</Stepper>
```

**Swift syntax:**
- `Stepper(value:, in: 0...359, step: 15) { label }` — `0...359` is a closed range (inclusive both ends); `step:` is the increment; the trailing `{ }` is the label content. TS: `min`/`max`/`step` props.
- `Int(x.rounded())` / `Double($0)` — explicit numeric casts (Swift won't implicitly convert `Double` ↔ `Int`). TS numbers are all `number`, so the casts vanish.

The stepper steps by 15° within `0...359`, converting between the stored `Double` and the `Int` it edits. Note `gradientHex2` is `String?` so its getter defaults: `Color(hex: slide.gradientHex2 ?? "#1E3A8A")` (the `??` is a nullish fallback — TS `slide.gradientHex2 ?? "#1E3A8A"`).

### Image / Video

Both follow the same shape — show the current filename if present, a "Choose…" button, and a destructive "Remove" when a file is set:

```swift
if let filename = slide.backgroundImageFilename {
    LabeledContent("File") {
        Text(filename).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
    }
}
HStack {
    Button("Choose image…") { pickImage() }
    if slide.backgroundImageFilename != nil {
        Spacer()
        Button("Remove", role: .destructive) {
            slide.backgroundImageFilename = nil
            onChange()
        }
    }
}
```

**TypeScript equivalent**

```tsx
<>
  {slide.backgroundImageFilename != null && (
    <LabeledContent label="File">
      <Text style={{ whiteSpace: "nowrap", textOverflow: "ellipsis", color: "var(--secondary)" }}>
        {slide.backgroundImageFilename}
      </Text>
    </LabeledContent>
  )}
  <Row>
    <button onClick={() => pickImage()}>Choose image…</button>
    {slide.backgroundImageFilename != null && (
      <>
        <Spacer />
        <button
          className="destructive"                  // analogy: role: .destructive
          onClick={() => { slide.backgroundImageFilename = null; onChange(); }}
        >
          Remove
        </button>
      </>
    )}
  </Row>
</>
```

**Swift syntax:**
- `Button("Remove", role: .destructive) { ... }` — `role:` is a semantic hint (`.destructive` renders red on macOS). TS analog: a CSS class / variant.
- `.truncationMode(.middle)` — ellipsize in the middle of the string (good for filenames). TS: `text-overflow: ellipsis` (no built-in middle mode).

`pickImage()` / `pickVideo()` open an `NSOpenPanel` restricted to the right content types, then import and store only the filename:

```swift
guard panel.runModal() == .OK, let url = panel.url else { return }
do {
    let filename = try MediaStorage.importFile(at: url)
    slide.backgroundImageFilename = filename
    onChange()
} catch {
    NSSound.beep()
}
```

**TypeScript equivalent**

```ts
const result = await panel.runModal();             // native open dialog (blocks)
if (result !== "OK" || panel.url == null) return;  // analogy: guard ... else { return }
try {
  const filename = MediaStorage.importFile(panel.url); // analogy: try (throwing call)
  slide.backgroundImageFilename = filename;
  onChange();
} catch {
  NSSound.beep();                                   // analogy: catch → just beep, no crash
}
```

**Swift syntax:**
- `guard panel.runModal() == .OK, let url = panel.url else { return }` — a multi-condition guard: both the modal result must be `.OK` *and* `panel.url` must unwrap, else bail. TS: an early-return `if`.
- `do { try f() } catch { ... }` — error handling; `try` marks a throwing call; `catch` (no value bound here) runs on failure. TS `try/catch`.
- `let filename = try MediaStorage.importFile(at: url)` — `at:` is the argument label. TS just `importFile(url)`.

If the import throws, it just beeps (no crash). Video allows `.movie, .mpeg4Movie, .quickTimeMovie`.

### `SwatchGrid`

A reusable 4-column grid of color buttons; the selected swatch gets a thicker accent border:

```swift
RoundedRectangle(cornerRadius: 6)
    .fill(Color(hex: hex))
    .overlay(RoundedRectangle(cornerRadius: 6)
        .strokeBorder(hex == selected ? Color.accentColor : Color.gray.opacity(0.3),
                      lineWidth: hex == selected ? 2 : 1))
```

**TypeScript equivalent**

```tsx
const columns = Array(4).fill({ flex: 1 });        // analogy: GridItem(.flexible()) × 4
<div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 6 }}>
  {palette.map(hex => (
    <button key={hex} onClick={() => onSelect(hex)} style={{ all: "unset" }}>
      <div
        style={{
          height: 28, borderRadius: 6,
          background: Color.fromHex(hex),
          border: `${hex === selected ? 2 : 1}px solid ${hex === selected ? "var(--accent)" : "rgba(128,128,128,0.3)"}`,
        }}
      />
    </button>
  ))}
</div>
```

**Swift syntax:**
- `ForEach(palette, id: \.self) { hex in ... }` — iterate, using each string itself (`\.self`) as the identity key. TS analog: `palette.map(hex => <... key={hex}>)`.
- `hex == selected ? A : B` — ternary inline in a modifier; TS the same.
- `.overlay(...)` — draws the border rectangle on top of the filled swatch.

## How it connects

It edits the `Slide`'s background fields only. The parent inspector hosts it under the "Slide" tab and provides `slide` + `onChange`. Imported media goes through `MediaStorage` (which copies the file under Application Support/Jerusalem/Media) so the app owns a stable copy; only the filename is persisted, and the renderer/live output resolve it later. `onChange()` flags `Slide.isManuallyEdited` and triggers re-render/re-arm.

## Gotchas / why it matters

- **Hex strings, not `Color`s, are the source of truth.** The custom `ColorPicker` bindings always round-trip through `Color(hex:)`/`hexString`. Don't store a `Color` on the model.
- **Files are imported, not referenced in place.** Always go through `MediaStorage.importFile`; storing an arbitrary external path would break "never fail on Sunday" if the user moves/deletes the original.
- **Kind-gated controls** are intentional — only the controls the renderer honors are shown for the current kind. If you add a background kind, add both the enum case/tag and its control block.
- Import failure beeps rather than crashing; keep that resilience.
