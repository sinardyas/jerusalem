# `SlideBackgroundSection.swift`

> The inspector's "Background (slide)" section: pick the background kind (color / gradient / image / video) and edit only the controls relevant to that kind, including a swatch palette and file pickers.

**Location:** `Sources/Jerusalem/Editor/SlideBackgroundSection.swift`
**Role:** SwiftUI view (plus a small reusable `SwatchGrid` view)

## What it does (plain English)

This section sets the whole slide's background. A segmented control at the top chooses one of four kinds — Color, Gradient, Image, Video — and the controls below swap to match. Pick Color and you get a quick swatch palette plus a full color picker; pick Gradient and you get two colors and an angle stepper; pick Image or Video and you get a "Choose…" button (a native macOS file picker) plus a "Remove" button. Showing only the relevant controls keeps the operator from setting, say, a gradient angle the renderer would ignore.

Every change writes straight onto the `Slide` model fields (`backgroundKind`, `backgroundColorHex`, `gradientHex2`, `gradientAngle`, `backgroundImageFilename`, `backgroundVideoFilename`) and then calls `onChange()`. Image/video files are copied into the app's media store first via `MediaStorage.importFile`, and only the returned filename is stored.

## Swift you'll meet in this file

- `@Bindable var slide: Slide` — the SwiftData model being edited; field writes here are persisted.
- `var onChange: () -> Void` — parent callback fired after each edit.
- `private static let palette: [String]` — a type-level constant array (shared by all instances); referenced as `Self.palette`.
- `Binding(get:set:)` — custom two-way bindings that transform on read/write (e.g. enum ↔ picker tag, `Color` ↔ hex string).
- `@ViewBuilder private var colorControls: some View` — computed sub-views, one per kind, selected by a `switch`.
- `T?` optionals: `slide.backgroundImageFilename` is `String?`; `if let filename = ...` renders the file row only when set; `!= nil` gates the Remove button.
- `guard ... else { return }` — early-exit if a condition fails (e.g. the file panel was cancelled).
- `do { try ... } catch { ... }` — Swift error handling; `try` calls a throwing function, `catch` handles failure (`NSSound.beep()`).
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

The stepper steps by 15° within `0...359`, converting between the stored `Double` and the `Int` it edits. Note `gradientHex2` is `String?` so its getter defaults: `Color(hex: slide.gradientHex2 ?? "#1E3A8A")` (the `??` is a nullish fallback).

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

## How it connects

It edits the `Slide`'s background fields only. The parent inspector hosts it under the "Slide" tab and provides `slide` + `onChange`. Imported media goes through `MediaStorage` (which copies the file under Application Support/Jerusalem/Media) so the app owns a stable copy; only the filename is persisted, and the renderer/live output resolve it later. `onChange()` flags `Slide.isManuallyEdited` and triggers re-render/re-arm.

## Gotchas / why it matters

- **Hex strings, not `Color`s, are the source of truth.** The custom `ColorPicker` bindings always round-trip through `Color(hex:)`/`hexString`. Don't store a `Color` on the model.
- **Files are imported, not referenced in place.** Always go through `MediaStorage.importFile`; storing an arbitrary external path would break "never fail on Sunday" if the user moves/deletes the original.
- **Kind-gated controls** are intentional — only the controls the renderer honors are shown for the current kind. If you add a background kind, add both the enum case/tag and its control block.
- Import failure beeps rather than crashing; keep that resilience.
