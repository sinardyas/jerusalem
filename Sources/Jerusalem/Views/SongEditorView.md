# `SongEditorView.swift`

> Phase 6 song editor: type lyrics with `[Verse 1]` / `[Chorus]` markers, set lines-per-slide, and watch the slide grid regenerate.

**Location:** `Sources/Jerusalem/Views/SongEditorView.swift`
**Role:** SwiftUI view — content-authoring editor (song), hosted under the slide-editor window flow

## What it does (plain English)

This is the authoring form for a song. You give it a title and author, set how many lyric lines go on each slide, and type the lyrics in a big text box, wrapping each section header in brackets on its own line (`[Verse 1]`, `[Chorus]`, `[Bridge]`, `[Tag]`). As you type, slides regenerate automatically (debounced so it isn't thrashing the database on every keystroke).

The lyrics block is the **canonical authored source** — `ContentRebuilder` materializes the actual `Slide` rows from it, which the renderer and live navigation then consume. A "Derived slides" section shows the resulting slide/section counts and, if you've manually tweaked slides in the WYSIWYG editor, offers a destructive "Restore auto-generated slides" button.

Per project memory (Phase 8.5), operator-side editing was removed; this view now lives under the dedicated editor window's content rail.

## Swift you'll meet in this file

- **`struct SongEditorView: View { var body: some View }`** — SHAPE: value-type `struct` conforming to `View`, with a `body`. TS analog: `function SongEditorView(): JSX.Element { return (...) }`; `some View` ≈ `: JSX.Element`.
- **`@Bindable var item: Item`** — makes the SwiftData model bindable so `$item.title` / `$item.linesPerSlide` are two-way field bindings. TS analog: a model object plus setters.
- **`@Environment(LiveState.self) private var live`** — Context-style injection of the shared live engine. TS analog: `useContext(LiveStateContext)`.
- **`@State private var lyrics: String = ""`** — `useState`; a local draft buffer for the lyrics text (kept separate from the model and flushed on debounce / disappear). TS analog: `const [lyrics, setLyrics] = useState("")`.
- **`@State private var rebuildTask: Task<Void, Never>?`** — a cancellable async task handle for the debounce; `T?` is "T or null". TS analog: a cancellable `Promise | null`.
- **`Form { Section { ... } }`** — a grouped settings-style form; `.formStyle(.grouped)` gives the macOS inset look. TS analog: `<Form className="grouped">`.
- **`TextField("Title", text: $item.title)`** — a text input bound to a model field. TS analog: a controlled `<input>`.
- **`TextField(..., text: Binding(get:set:))`** — a custom two-way binding that maps `nil ⇄ ""` for the optional subtitle. TS analog: an `<input>` whose value/onChange convert empty string ↔ null.
- **`Stepper(value: $item.linesPerSlide, in: 1...8)`** — a +/- numeric control clamped to a range. TS analog: `<input type="number" min={1} max={8} />`.
- **`TextEditor(text: $lyrics)`** — a multi-line text area. TS analog: `<textarea>`.
- **`.onChange(of:) { _, newValue in ... }`** — runs a side effect when a value changes (old, new args; `_` ignores old). TS analog: `useEffect(..., [value])` / inline handler.
- **`.onAppear` / `.onChange(of: item.persistentModelID)` / `.onDisappear`** — lifecycle hooks (mount / item-swap / unmount). TS analog: `useEffect`.
- **`Task { @MainActor in try? await Task.sleep(...) }`** — schedule async work on the main actor; `try?` discards a throwing error as `nil`. TS analog: `(async () => { await sleep(...) })()`.
- **`Button(role: .destructive) { ... }`** — a destructive (red) button. TS analog: `<button className="destructive">`.

## Code walkthrough

### Title / author / lines-per-slide

```swift
Section("Song") {
    TextField("Title", text: $item.title)
    TextField("Author (subtitle)", text: Binding(
        get: { item.subtitle ?? "" },
        set: { item.subtitle = $0.isEmpty ? nil : $0 }))
    Stepper(value: $item.linesPerSlide, in: 1...8) {
        LabeledContent("Lines per slide", value: "\(item.linesPerSlide)")
    }
    .onChange(of: item.linesPerSlide) { _, _ in
        ContentRebuilder.rebuild(item)
        rearmIfShowing()
    }
}
```

**TypeScript equivalent**

```tsx
<Section title="Song">
  <input placeholder="Title" value={item.title} onChange={e => (item.title = e.target.value)} />
  {/* analogy: Binding(get:set:) -> a controlled input mapping "" <-> null */}
  <input
    placeholder="Author (subtitle)"
    value={item.subtitle ?? ""}
    onChange={e => (item.subtitle = e.target.value === "" ? null : e.target.value)}
  />
  {/* analogy: Stepper -> clamped number input */}
  <NumberStepper
    min={1}
    max={8}
    value={item.linesPerSlide}
    onChange={v => {
      item.linesPerSlide = v;
      ContentRebuilder.rebuild(item);
      rearmIfShowing();
    }}
    label={<LabeledRow label="Lines per slide" value={`${item.linesPerSlide}`} />}
  />
</Section>
```

**Swift syntax:**
- `Binding(get: { item.subtitle ?? "" }, set: { item.subtitle = $0.isEmpty ? nil : $0 })` — a hand-built two-way binding: `get` supplies the display value, `set` writes back; `$0` is the new string. Here `nil ⇄ ""`. TS analog: a controlled input with custom conversions.
- `Stepper(value: $item.linesPerSlide, in: 1...8) { label }` — two-way bound, clamped to the `1...8` closed range; trailing closure is the label. TS analog: `<input type="number" min={1} max={8} />`.
- `"\(item.linesPerSlide)"` — string interpolation. TS analog: `` `${item.linesPerSlide}` ``.

Title binds straight to the model. The author field uses a hand-written `Binding` that converts an empty string to `nil` (so a cleared author doesn't store `""`). The `Stepper` clamps lines-per-slide to 1...8, and changing it immediately rebuilds slides and re-arms.

### The lyrics editor (the canonical source)

```swift
Section {
    TextEditor(text: $lyrics)
        .font(.body.monospaced())
        ...
        .onChange(of: lyrics) { _, newValue in
            scheduleRebuild(newValue)
        }
} header: {
    Text("Lyrics")
} footer: {
    Text("""
    Wrap each section header in brackets on its own line:
    `[Verse 1]`, `[Chorus]`, `[Bridge]`, `[Tag]`.
    Slides regenerate as you type.
    """)
    ...
}
```

**TypeScript equivalent**

```tsx
<Section
  header={<Text>Lyrics</Text>}
  footer={
    <Text className="caption secondary">{`Wrap each section header in brackets on its own line:
\`[Verse 1]\`, \`[Chorus]\`, \`[Bridge]\`, \`[Tag]\`.
Slides regenerate as you type.`}</Text>
  }
>
  {/* analogy: TextEditor -> <textarea>; .font(.body.monospaced()) -> monospace */}
  <textarea
    style={{ fontFamily: "monospace", minHeight: 140 }}
    value={lyrics}
    onChange={e => { setLyrics(e.target.value); scheduleRebuild(e.target.value); }}
  />
</Section>
```

**Swift syntax:**
- `Text("""\n...\n""")` — a triple-quoted **multi-line string literal**. TS analog: a template literal (backticks) spanning lines.
- `.font(.body.monospaced())` — chained font modifier producing a monospaced body font. TS analog: `font-family: monospace`.

A monospaced multi-line text area bound to the local `lyrics` draft. Each keystroke calls `scheduleRebuild`, which debounces. The footer documents the bracket-header convention. (The triple-quoted string is a multi-line literal.)

### Derived-slides readout + reset

```swift
Section("Derived slides") {
    LabeledContent("Slides", value: "\(item.orderedSlides.count)")
    LabeledContent("Sections", value: "\(item.orderedSongSections.count)")
    if ContentRebuilder.hasManualEdits(item) {
        Button(role: .destructive) {
            ContentRebuilder.resetToAutoDerived(item)
            rearmIfShowing()
        } label: {
            Label("Restore auto-generated slides", systemImage: "arrow.uturn.backward")
        }
    }
}
```

**TypeScript equivalent**

```tsx
<Section title="Derived slides">
  <LabeledRow label="Slides" value={`${item.orderedSlides.length}`} />
  <LabeledRow label="Sections" value={`${item.orderedSongSections.length}`} />
  {ContentRebuilder.hasManualEdits(item) && (
    <button
      className="destructive"
      onClick={() => { ContentRebuilder.resetToAutoDerived(item); rearmIfShowing(); }}
    >
      <Icon name="arrow.uturn.backward" /> Restore auto-generated slides
    </button>
  )}
</Section>
```

**Swift syntax:**
- `if ContentRebuilder.hasManualEdits(item) { Button(role: .destructive) { action } label: { view } }` — conditionally include the destructive button; `role: .destructive` styles it red. TS analog: `cond && <button className="destructive" .../>`.

Shows the live slide/section counts. The reset button only appears when the slides have been manually edited (so the regeneration from lyrics has been overridden); pressing it discards the manual edits and re-derives, then re-arms.

### Lifecycle and draft sync

```swift
.onAppear { lyrics = ContentRebuilder.lyricsText(for: item) }
.onChange(of: item.persistentModelID) { _, _ in
    lyrics = ContentRebuilder.lyricsText(for: item)
}
.onDisappear {
    rebuildTask?.cancel()
    // Flush a pending edit so we don't lose the last keystrokes.
    ContentRebuilder.setLyrics(lyrics, on: item)
}
```

**TypeScript equivalent**

```tsx
// analogy: .onAppear + .onChange(of: item.id) + .onDisappear -> one useEffect keyed on the item
useEffect(() => {
  setLyrics(ContentRebuilder.lyricsText(item));   // load on mount AND item-swap
  return () => {                                   // .onDisappear cleanup
    rebuildTask?.cancel();
    ContentRebuilder.setLyrics(lyrics, item);      // flush the last keystrokes
  };
}, [item.persistentModelID]);
```

On appear (and whenever the edited item changes identity) the draft is reloaded from the model via `ContentRebuilder.lyricsText`. On disappear it **cancels any pending debounce and flushes the current draft** so the last keystrokes aren't lost — important because the debounce might not have fired yet when the window closes.

### The debounce + re-arm

```swift
private func scheduleRebuild(_ text: String) {
    rebuildTask?.cancel()
    rebuildTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        ContentRebuilder.setLyrics(text, on: item)
        rearmIfShowing()
    }
}

private func rearmIfShowing() {
    live.arm(LiveState.programSlides(for: item))
}
```

**TypeScript equivalent**

```ts
function scheduleRebuild(text: string): void {
  rebuildTask?.cancel();
  // analogy: Task { @MainActor in ... } -> async run on the main thread
  rebuildTask = runCancellable(async () => {
    await sleep(350);
    if (rebuildTask?.isCancelled) return;     // guard !Task.isCancelled else { return }
    ContentRebuilder.setLyrics(text, item);
    rearmIfShowing();
  });
}

function rearmIfShowing(): void {
  live.arm(LiveState.programSlides(item));
}
```

**Swift syntax:**
- `func scheduleRebuild(_ text: String)` — `_` = no external label, so it's called positionally. TS analog: a plain positional param.
- `rebuildTask?.cancel()` — optional-chained call; no-op if `nil`. TS analog: `rebuildTask?.cancel()`.
- `Task { @MainActor in try? await Task.sleep(for: .milliseconds(350)) }` — async work on the main actor; `try?` swallows a thrown cancellation as `nil`. TS analog: `(async () => { await sleep(350) })()`.
- `guard !Task.isCancelled else { return }` — bail if the task was cancelled meanwhile. TS analog: `if (cancelled) return;`.

`scheduleRebuild` cancels the previous task and starts a new one that waits 350 ms; if it wasn't cancelled, it writes the lyrics through `ContentRebuilder.setLyrics` and re-arms. `rearmIfShowing` re-loads this item's slides into `LiveState` so the grid and the inspector's "Next" preview reflect the new slides immediately.

## How it connects

- Writes the authored lyrics into the model via the **`ContentRebuilder`** namespace (`setLyrics`, `rebuild`, `lyricsText`, `hasManualEdits`, `resetToAutoDerived`), which materializes the `Slide` rows the renderer/navigation consume.
- Calls **`live.arm(LiveState.programSlides(for: item))`** after edits so the operator's grid + live state re-arm (without changing the audience screen until the operator acts).
- Bound directly to the `@Bindable` `Item` model; SwiftData autosaves the field edits.

## Gotchas / why it matters

- **Lyrics are the source of truth** — slides are *derived*; the reset button exists precisely because the WYSIWYG editor can override that derivation, and you sometimes want to go back.
- **Debounce avoids SwiftData thrash** — 350 ms keeps typing smooth; the `.onDisappear` flush guarantees the final edit still lands.
- **Re-arm, not go-live** — edits re-arm the program; per the value-snapshot rule the live output doesn't change until the operator deliberately advances or clicks.
- **Empty-string-to-nil binding** for the subtitle keeps the model clean (no stored `""`).
