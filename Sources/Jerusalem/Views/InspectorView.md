# `InspectorView.swift`

> The operator window's trailing inspector: a live-output mirror (current + next), panic controls, the transition picker, and selected-item metadata.

**Location:** `Sources/Jerusalem/Views/InspectorView.swift`
**Role:** SwiftUI view — the operator-side inspector panel (the right column of the operator window)

## What it does (plain English)

This is the panel pinned to the right edge of the operator window. Its top section is a **mirror of the audience output**: a small preview of what's live right now (a slide, a video, or BLACK/LOGO/empty placeholders), a thumbnail of what's coming next, three big panic buttons, and a picker for the transition style. Below that is read-only metadata about the selected item (title, kind, slide count), and — for video items only — a section of loop/mute/end-behavior controls.

Note this is the **operator-side** inspector, a different file from the slide editor's `SlideInspectorView`. Here the operator *watches and reacts* during a service; it doesn't edit slide geometry.

## Swift you'll meet in this file

- **`let item: Item?`** — a plain stored property; `Item?` means "an `Item` or `null`". This view is handed the currently selected item (or nothing).
- **`@Environment(LiveState.self) private var live`** — Context-style injection of the shared `LiveState` singleton.
- **`@Bindable var live = live`** — promotes the injected `live` to a *bindable* local so you can make two-way bindings (`$live.transition`) into its properties. Like wrapping a context object so you can pass `value`+`onChange` for a field.
- **`switch live.content { case .slide(let renderable): ... }`** — an exhaustive `switch` over an enum with *associated values*. `case .slide(let renderable)` both matches the case and binds the payload to `renderable` (like destructuring a tagged union).
- **`@ViewBuilder private var liveBox: some View`** — `@ViewBuilder` lets a property/function return different views per branch (so an `if`/`switch` can produce a view). `some View` is an opaque "some kind of View" return.
- **`ForEach(TransitionStyle.allCases) { Text($0.label).tag($0) }`** — `.map` over enum cases to build picker options; `.tag` marks each option's value.
- **`$live.transition`** — the `$` makes a two-way Binding to that field, so the `Picker` reads and writes it.
- **`.overlay(...)`, `.clipShape(...)`, `.aspectRatio(...)`** — chained view modifiers, like wrapping an element in styling wrappers.

## Code walkthrough

The `body` first promotes `live` to a `@Bindable` local, then returns a grouped `Form` (a settings-style stacked list of sections):

```swift
var body: some View {
    @Bindable var live = live
    return Form {
        Section("Live") {
            liveBox
            nextRow
            panicRow
            Picker("Transition", selection: $live.transition) {
                ForEach(TransitionStyle.allCases) { Text($0.label).tag($0) }
            }
        }
        Section("Item") {
            LabeledContent("Title", value: item?.title ?? "—")
            LabeledContent("Kind", value: item?.kind.displayName ?? "—")
            LabeledContent("Slides", value: item.map { "\($0.slides.count)" } ?? "—")
        }
        if let item, item.kind == .media {
            VideoSettingsSection(item: item)
        }
    }
    .formStyle(.grouped)
}
```

The "Item" section uses `??` to fall back to a dash when nothing is selected. `item.map { "\($0.slides.count)" }` is optional-map — it only runs the closure if `item` is non-null, otherwise yields the `"—"` fallback. The last `if let item, item.kind == .media` shows video controls only for media items.

### `liveBox` — the current-output mirror

```swift
@ViewBuilder private var liveBox: some View {
    switch live.content {
    case .slide(let renderable):
        SlideStageView(renderable: renderable)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.8), lineWidth: 2))
    case .video(let cue):
        videoBox(cue)
    case .black:
        labelBox("BLACK")
    case .logo:
        labelBox("LOGO")
    case .empty:
        labelBox("Nothing live")
    }
}
```

`live.content` is the resolved snapshot of what's on the audience screen. A live slide renders through `SlideStageView` with a red border (so the operator sees "this is live"); a live video uses `videoBox`; the panic/empty states show a black box with a caption via `labelBox`.

### `nextRow` — the on-deck preview

```swift
@ViewBuilder private var nextRow: some View {
    if let next = live.nextProgramSlide {
        switch next.kind {
        case .slide(let renderable):
            LabeledContent("Next") {
                RenderableSlideView(renderable: renderable)
                    .frame(width: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        case .video:
            LabeledContent("Next", value: "Video")
        }
    } else {
        LabeledContent("Next", value: "End")
    }
}
```

Shows a small thumbnail of the next slide, the word "Video" for an upcoming clip, or "End" when there's nothing after the current slide.

### `panicRow` and `panicButton`

```swift
private func panicButton(_ title: String, _ panic: LiveState.Panic, systemImage: String) -> some View {
    Button { live.setPanic(panic) } label: {
        Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .tint(live.panic == panic ? .red : nil)
}
```

Three buttons — Black / Clear / Logo — each calling `live.setPanic(...)`. The active panic state tints red (`.tint(... ? .red : nil)`), so the operator can see at a glance which override is engaged. These mirror the **B / C / L** keyboard shortcuts in `OperatorView`.

### `labelBox` and `videoBox`

`labelBox` is a black 16:9 rounded rectangle with a centered caption (used for BLACK/LOGO/Nothing-live). `videoBox` shows a **muted** preview of a live clip — it copies the cue and forces `previewCue.muted = true` so the inspector preview is silent while audio stays on the audience output:

```swift
private func videoBox(_ cue: VideoCue) -> some View {
    var previewCue = cue
    previewCue.muted = true
    return ZStack {
        Color.black
        VideoPlayerView(cue: previewCue)
    }
    ...
}
```

### `VideoSettingsSection`

A separate small view bound to a `.media` item via `@Bindable`, giving Loop / Muted toggles and an "On end" picker:

```swift
struct VideoSettingsSection: View {
    @Bindable var item: Item
    var body: some View {
        Section("Video") {
            Toggle("Loop", isOn: $item.videoLoops)
            Toggle("Muted", isOn: $item.videoMuted)
            Picker("On end", selection: $item.videoEndBehavior) {
                ForEach(VideoEndBehavior.allCases) { Text($0.label).tag($0) }
            }
        }
    }
}
```

`$item.videoLoops` etc. are two-way bindings straight into the SwiftData model. Per its doc comment, changes "take effect the next time the item is armed," and this section is **reused by the slide editor's content rail** for media items.

## How it connects

- Reads everything live from **`LiveState`** via `@Environment`: `live.content` (current output), `live.nextProgramSlide` (on-deck), `live.panic` / `live.setPanic(...)` (panic), and `$live.transition` (transition picker).
- Receives the selected **`item: Item?`** as a prop from `OperatorView` for the metadata and the conditional video section.
- Renders previews through the shared rendering views (`SlideStageView`, `RenderableSlideView`) and `VideoPlayerView` — the same pipeline that feeds the audience screen, so the mirror is faithful.
- `VideoSettingsSection` writes directly to the model and is shared with the slide editor.

## Gotchas / why it matters

- **It's a mirror, not a control of geometry** — this is the operator's at-a-glance window into the audience output, plus emergency controls. The panic buttons here are the click-equivalent of the B/C/L keys.
- **Muted preview** — the inspector's video preview is forcibly muted so two audio streams don't play; only the audience output makes sound.
- **`@Bindable var live = live`** is required to build `$live.transition`; you can't make a binding into an `@Environment` value without first promoting it to a bindable local.
- **Value-snapshot separation** — `live.content` is a resolved snapshot, so this mirror reflects exactly what's on the audience screen, independent of any in-progress model edits elsewhere.
