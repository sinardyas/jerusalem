# `InspectorView.swift`

> The operator window's trailing inspector: a live-output mirror (current + next), panic controls, the transition picker, and selected-item metadata.

**Location:** `Sources/Jerusalem/Views/InspectorView.swift`
**Role:** SwiftUI view — the operator-side inspector panel (the right column of the operator window)

## What it does (plain English)

This is the panel pinned to the right edge of the operator window. Its top section is a **mirror of the audience output**: a small preview of what's live right now (a slide, a video, or BLACK/LOGO/empty placeholders), a thumbnail of what's coming next, three big panic buttons, and a picker for the transition style. Below that is read-only metadata about the selected item (title, kind, slide count), and — for video items only — a section of loop/mute/end-behavior controls.

Note this is the **operator-side** inspector, a different file from the slide editor's `SlideInspectorView`. Here the operator *watches and reacts* during a service; it doesn't edit slide geometry.

## Swift you'll meet in this file

- **`struct InspectorView: View { var body: some View }`** — SHAPE: value-type `struct` conforming to `View`, with a `body`. TS analog: `function InspectorView(): JSX.Element { return (...) }`; `some View` ≈ `: JSX.Element`.
- **`let item: Item?`** — a plain stored (immutable) property; `Item?` means "an `Item` or `null`". TS analog: a readonly prop `item: Item | null`.
- **`@Environment(LiveState.self) private var live`** — Context-style injection of the shared `LiveState` singleton. TS analog: `const live = useContext(LiveStateContext)`.
- **`@Bindable var live = live`** — promotes the injected `live` to a *bindable* local so you can make two-way bindings (`$live.transition`) into its properties. TS analog: wrapping a context object so you can pass `value`+`onChange` for a field.
- **`switch live.content { case .slide(let renderable): ... }`** — an exhaustive `switch` over an enum with *associated values*. SHAPE: `case .slide(let renderable)` matches the case AND binds the payload. TS analog: `switch (live.content.kind)` on a tagged union, destructuring the payload.
- **`@ViewBuilder private var liveBox: some View`** — `@ViewBuilder` lets a property/function return different views per branch (so an `if`/`switch` can produce a view). TS analog: a function returning JSX with `if`/`switch`.
- **`ForEach(TransitionStyle.allCases) { Text($0.label).tag($0) }`** — `.map` over enum cases to build picker options; `.tag` marks each option's value; `$0` is the first closure arg. TS analog: `TransitionStyle.allCases.map(s => <option value={s}>{s.label}</option>)`.
- **`$live.transition`** — the `$` makes a two-way Binding to that field, so the `Picker` reads and writes it. TS analog: `value`+`onChange` together.
- **`.overlay(...)`, `.clipShape(...)`, `.aspectRatio(...)`** — chained view modifiers (`.modifier` chaining), like wrapping an element in styling wrappers. TS analog: nested styling wrappers / className chains.

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

**TypeScript equivalent**

```tsx
function InspectorView({ item }: { item: Item | null }): JSX.Element {
  const live = useContext(LiveStateContext); // already "bindable" in React

  return (
    <Form className="grouped">
      <Section title="Live">
        {liveBox}
        {nextRow}
        {panicRow}
        {/* analogy: Picker -> <select>; .tag marks each option's value */}
        <select value={live.transition} onChange={e => live.setTransition(e.target.value)}>
          {TransitionStyle.allCases.map(s => (
            <option key={s} value={s}>{s.label}</option>
          ))}
        </select>
      </Section>

      <Section title="Item">
        <LabeledRow label="Title" value={item?.title ?? "—"} />
        <LabeledRow label="Kind" value={item?.kind.displayName ?? "—"} />
        <LabeledRow label="Slides" value={item ? `${item.slides.length}` : "—"} />
      </Section>

      {item && item.kind === "media" && <VideoSettingsSection item={item} />}
    </Form>
  );
}
```

**Swift syntax:**
- `@Bindable var live = live` — re-declares the environment `live` as a bindable local *inside* `body`. You can't make `$live.transition` from an `@Environment` value directly; this promotion is the workaround. TS analog: not needed — a context object is already mutable.
- `item?.title ?? "—"` — optional chaining (`?.`) then nullish-coalescing (`??`). TS analog: `item?.title ?? "—"`.
- `item.map { "\($0.slides.count)" } ?? "—"` — **optional map**: runs the closure only if `item` is non-null, else yields the `??` fallback. `$0` is the unwrapped `item`. TS analog: `item ? \`${item.slides.length}\` : "—"`.
- `if let item, item.kind == .media { ... }` — optional binding + boolean condition; both must pass. TS analog: `if (item && item.kind === "media")`.
- `.media` — shorthand for an enum case (`ItemKind.media`) where the type is inferred. TS analog: the string/union member `"media"`.

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

**TypeScript equivalent**

```tsx
// analogy: @ViewBuilder property -> a function returning JSX
function liveBox(): JSX.Element {
  // analogy: switch over a tagged union; `let renderable` destructures the payload
  switch (live.content.kind) {
    case "slide": {
      const renderable = live.content.renderable;
      return (
        <SlideStageView
          renderable={renderable}
          style={{ borderRadius: 8, border: "2px solid rgba(255,0,0,0.8)" }}
        />
      );
    }
    case "video":
      return videoBox(live.content.cue);
    case "black":
      return labelBox("BLACK");
    case "logo":
      return labelBox("LOGO");
    case "empty":
      return labelBox("Nothing live");
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

**TypeScript equivalent**

```tsx
function nextRow(): JSX.Element {
  const next = live.nextProgramSlide;
  if (next) {
    switch (next.kind.type) {
      case "slide":
        return (
          <LabeledRow label="Next">
            <RenderableSlideView
              renderable={next.kind.renderable}
              style={{ width: 96, borderRadius: 4 }}
            />
          </LabeledRow>
        );
      case "video":
        return <LabeledRow label="Next" value="Video" />;
    }
  } else {
    return <LabeledRow label="Next" value="End" />;
  }
}
```

**Swift syntax:**
- `if let next = live.nextProgramSlide { ... } else { ... }` — optional binding with an else branch. TS analog: `const next = ...; if (next) { ... } else { ... }`.
- `case .video:` (no `let`) — matches the case but ignores its payload. TS analog: a `case` that doesn't destructure.

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

**TypeScript equivalent**

```tsx
function panicButton(title: string, panic: Panic, systemImage: string): JSX.Element {
  return (
    <button
      className="bordered"
      style={{ color: live.panic === panic ? "red" : undefined, flex: 1 }}
      onClick={() => live.setPanic(panic)}
    >
      {/* analogy: Label = icon + text */}
      <Icon name={systemImage} /> {title}
    </button>
  );
}
```

**Swift syntax:**
- `func panicButton(_ title: String, _ panic: ..., systemImage: String)` — `_` before a parameter means *no external label* (call it positionally); `systemImage:` keeps its label. TS analog: positional vs. named-via-object args.
- `live.panic == panic ? .red : nil` — ternary; `.red` is `Color.red` shorthand, `nil` means "no tint". TS analog: `live.panic === panic ? "red" : undefined`.

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

**TypeScript equivalent**

```tsx
function videoBox(cue: VideoCue): JSX.Element {
  // VideoCue is a struct (value type): copying then mutating doesn't touch the original
  const previewCue = { ...cue, muted: true };
  return (
    // analogy: ZStack -> layered/absolute children
    <div style={{ position: "relative" }}>
      <div style={{ background: "black", position: "absolute", inset: 0 }} />
      <VideoPlayerView cue={previewCue} />
    </div>
  );
}
```

**Swift syntax:**
- `var previewCue = cue` then mutate — `cue` is a **struct (value type)**, so this is a *copy*; mutating `previewCue` leaves the original untouched. TS analog: `{ ...cue }` to copy before editing.
- `ZStack { ... }` — a trailing-closure container layering children back-to-front. TS analog: absolutely-positioned siblings.

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

**TypeScript equivalent**

```tsx
function VideoSettingsSection({ item }: { item: Item }): JSX.Element {
  return (
    <Section title="Video">
      {/* analogy: Toggle -> checkbox; $item.videoLoops -> two-way binding into the model */}
      <Toggle label="Loop" checked={item.videoLoops} onChange={v => (item.videoLoops = v)} />
      <Toggle label="Muted" checked={item.videoMuted} onChange={v => (item.videoMuted = v)} />
      <select
        value={item.videoEndBehavior}
        onChange={e => (item.videoEndBehavior = e.target.value)}
      >
        {VideoEndBehavior.allCases.map(b => (
          <option key={b} value={b}>{b.label}</option>
        ))}
      </select>
    </Section>
  );
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
