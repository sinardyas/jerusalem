# `SermonEditorView.swift`

> Phase 6 editor for sermon/text items: a title plus body paragraphs that become point slides, split by blank lines and by lines-per-slide.

**Location:** `Sources/Jerusalem/Views/SermonEditorView.swift`
**Role:** SwiftUI view — content-authoring editor (sermon/text), hosted under the slide-editor window flow

## What it does (plain English)

This is the authoring form for a sermon or plain-text item. You set a title and optional subtitle, choose how many lines go on each slide, and type the body in a large text box. Each paragraph (separated by a blank line) becomes its own point/bullet slide; a long paragraph is split further by `linesPerSlide`. Slides regenerate as you type (debounced).

It's almost identical in shape to `SongEditorView`, but the body is split via `SlideSplitter` rules instead of bracketed section markers. A "Derived slides" section shows the slide count and offers a "Restore auto-generated slides" button when the slides have been manually edited.

Per project memory (Phase 8.5), operator-side editing was removed; this view now lives under the dedicated editor window's content rail.

## Swift you'll meet in this file

- **`struct SermonEditorView: View { var body: some View }`** — SHAPE: value-type `struct` conforming to `View`, with a `body`. TS analog: `function SermonEditorView(): JSX.Element { return (...) }`; `some View` ≈ `: JSX.Element`.
- **`@Bindable var item: Item`** — bindable SwiftData model so `$item.title` / `$item.linesPerSlide` are two-way bindings. TS analog: a model object plus setters.
- **`@Environment(LiveState.self) private var live`** — injected shared live engine. TS analog: `useContext(LiveStateContext)`.
- **`@State private var bodyDraft: String = ""`** — `useState`; a local draft buffer for the body text, flushed on debounce / disappear. TS analog: `const [bodyDraft, setBodyDraft] = useState("")`.
- **`@State private var rebuildTask: Task<Void, Never>?`** — cancellable async handle for the debounce. SHAPE: `T?` = "T or null". TS analog: a cancellable `Promise | null`.
- **`Form { Section { ... } }` / `.formStyle(.grouped)`** — grouped settings-style form. TS analog: `<Form className="grouped">`.
- **`TextField(..., text: Binding(get:set:))`** — a custom binding mapping `nil ⇄ ""` for the optional subtitle. TS analog: an `<input>` whose value/onChange convert empty string ↔ null.
- **`Stepper(value: $item.linesPerSlide, in: 1...8)`** — clamped +/- numeric control. TS analog: `<input type="number" min={1} max={8} />`.
- **`TextEditor(text: $bodyDraft)`** — multi-line text area; `.scrollContentBackground(.hidden)` + `.background(...)` give it a custom rounded backdrop. TS analog: `<textarea>`.
- **`.onChange(of:) { _, newValue in ... }`** — side-effect on value change; `_` drops the old value. TS analog: `useEffect(..., [value])` or an inline handler.
- **`.onAppear` / `.onChange(of: item.persistentModelID)` / `.onDisappear`** — lifecycle hooks. TS analog: `useEffect` (mount / dep-change / cleanup).
- **`Task { @MainActor in try? await Task.sleep(...) }`** — debounce on the main actor. TS analog: `(async () => { await sleep(...) })()`.

## Code walkthrough

### Title / subtitle / lines-per-slide

```swift
Section("Item") {
    TextField("Title", text: $item.title)
        .onChange(of: item.title) { _, _ in
            ContentRebuilder.rebuild(item)
            rearm()
        }
    TextField("Subtitle", text: Binding(
        get: { item.subtitle ?? "" },
        set: { item.subtitle = $0.isEmpty ? nil : $0 }))
    Stepper(value: $item.linesPerSlide, in: 1...8) {
        LabeledContent("Lines per slide", value: "\(item.linesPerSlide)")
    }
    .onChange(of: item.linesPerSlide) { _, _ in
        ContentRebuilder.rebuild(item)
        rearm()
    }
}
```

**TypeScript equivalent**

```tsx
<Section title="Item">
  <input
    placeholder="Title"
    value={item.title}
    onChange={e => {
      item.title = e.target.value;
      ContentRebuilder.rebuild(item);
      rearm();
    }}
  />
  {/* analogy: Binding(get:set:) -> a controlled input mapping "" <-> null */}
  <input
    placeholder="Subtitle"
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
      rearm();
    }}
    label={<LabeledRow label="Lines per slide" value={`${item.linesPerSlide}`} />}
  />
</Section>
```

**Swift syntax:**
- `TextField("Subtitle", text: Binding(get: { ... }, set: { ... }))` — a hand-built two-way binding: `get` returns the displayed value, `set` writes it back; `$0` in `set` is the new string. Here it maps `nil ⇄ ""`. TS analog: a controlled input with custom value/onChange conversions.
- `item.subtitle = $0.isEmpty ? nil : $0` — assign `nil` (null) when empty, else the string. TS analog: `e.target.value === "" ? null : e.target.value`.
- `Stepper(value: $item.linesPerSlide, in: 1...8) { label }` — a stepper bound two-way and clamped to the `1...8` closed range; the trailing closure is its label. TS analog: a number input with `min`/`max`.

Title and lines-per-slide each trigger an immediate `ContentRebuilder.rebuild(item)` + `rearm()` on change (the title can affect the title slide). The subtitle uses the empty-string-to-`nil` binding so a cleared field doesn't store `""`.

### The body editor

```swift
Section {
    TextEditor(text: $bodyDraft)
        .font(.body)
        .frame(minHeight: 140)
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
        .onChange(of: bodyDraft) { _, newValue in
            scheduleRebuild(newValue)
        }
} header: {
    Text("Body")
} footer: {
    Text("Separate points with a blank line. Each point becomes its own slide.")
        ...
}
```

**TypeScript equivalent**

```tsx
<Section
  header={<Text>Body</Text>}
  footer={<Text className="caption secondary">Separate points with a blank line. Each point becomes its own slide.</Text>}
>
  {/* analogy: TextEditor -> <textarea> */}
  <textarea
    style={{ minHeight: 140, padding: 8, borderRadius: 6, background: "var(--secondary-bg)" }}
    value={bodyDraft}
    onChange={e => { setBodyDraft(e.target.value); scheduleRebuild(e.target.value); }}
  />
</Section>
```

A multi-line area bound to the `bodyDraft` local. Each edit calls `scheduleRebuild` (debounced). The footer documents the blank-line-separates-points rule.

### Derived-slides readout + reset

```swift
Section("Derived slides") {
    LabeledContent("Slides", value: "\(item.orderedSlides.count)")
    if ContentRebuilder.hasManualEdits(item) {
        Button(role: .destructive) {
            ContentRebuilder.resetToAutoDerived(item)
            rearm()
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
  {ContentRebuilder.hasManualEdits(item) && (
    <button
      className="destructive"
      onClick={() => { ContentRebuilder.resetToAutoDerived(item); rearm(); }}
    >
      <Icon name="arrow.uturn.backward" /> Restore auto-generated slides
    </button>
  )}
</Section>
```

**Swift syntax:**
- `if ContentRebuilder.hasManualEdits(item) { ... }` — a plain `if` inside a view builder conditionally includes the button. TS analog: `cond && <button .../>`.

Shows the current slide count; the reset button appears only when manual slide edits exist, and discards them to re-derive from the body, then re-arms.

### Lifecycle and draft sync

```swift
.onAppear { bodyDraft = item.bodyText ?? "" }
.onChange(of: item.persistentModelID) { _, _ in bodyDraft = item.bodyText ?? "" }
.onDisappear {
    rebuildTask?.cancel()
    ContentRebuilder.setBody(bodyDraft, on: item)
}
```

**TypeScript equivalent**

```tsx
// analogy: .onAppear + .onChange(of: item.id) + .onDisappear -> one useEffect
useEffect(() => {
  setBodyDraft(item.bodyText ?? "");          // load on mount AND item-swap
  return () => {                              // .onDisappear cleanup
    rebuildTask?.cancel();
    ContentRebuilder.setBody(bodyDraft, item); // flush the last keystrokes
  };
}, [item.persistentModelID]);
```

The draft loads from `item.bodyText` on appear (and on item-swap). On disappear it cancels the pending debounce and **flushes** the current body via `ContentRebuilder.setBody`, so the last keystrokes survive a window close.

### Debounce + re-arm

```swift
private func scheduleRebuild(_ text: String) {
    rebuildTask?.cancel()
    rebuildTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        ContentRebuilder.setBody(text, on: item)
        rearm()
    }
}

private func rearm() {
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
    if (rebuildTask?.isCancelled) return;   // guard !Task.isCancelled else { return }
    ContentRebuilder.setBody(text, item);
    rearm();
  });
}

function rearm(): void {
  live.arm(LiveState.programSlides(item));
}
```

**Swift syntax:**
- `func scheduleRebuild(_ text: String)` — `_` means no external argument label (call it positionally: `scheduleRebuild(newValue)`). TS analog: a plain positional param.
- `rebuildTask?.cancel()` — optional-chained call: only cancels if a task exists. TS analog: `rebuildTask?.cancel()`.
- `Task { @MainActor in ... }` — async work pinned to the main actor; `try? await Task.sleep` awaits and swallows errors. TS analog: `(async () => { await sleep(...) })()`.

The familiar pattern: cancel-and-replace a 350 ms task; if it survives, write the body through `ContentRebuilder.setBody` and re-arm the program so the grid and the inspector's "Next" preview update.

## How it connects

- Materializes slides through the **`ContentRebuilder`** namespace (`setBody`, `rebuild`, `hasManualEdits`, `resetToAutoDerived`); the underlying split rules live in `SlideSplitter` (paragraphs → points, `linesPerSlide` for long ones).
- Re-arms the live program via **`live.arm(LiveState.programSlides(for: item))`** after edits (no audience change until the operator acts).
- Bound to the `@Bindable` `Item`; SwiftData autosaves field edits.

## Gotchas / why it matters

- **Body is the source of truth**; slides are derived. The reset button reverses any manual WYSIWYG-editor overrides.
- **Title/lines rebuild immediately**, but body edits are debounced (350 ms) — the body is the high-frequency field, so it's the one that's throttled.
- **`.onDisappear` flush** guarantees the final body edit lands even if the debounce hadn't fired.
- **Re-arm vs. go-live** — edits re-arm only; the value-snapshot separation keeps the audience screen stable until the operator advances.
- This file is a near-twin of `SongEditorView`; the meaningful difference is *blank-line paragraph splitting* (sermon/text) vs. *bracketed section markers* (song).
