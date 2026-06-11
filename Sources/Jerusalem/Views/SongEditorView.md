# `SongEditorView.swift`

> Phase 6 song editor: type lyrics with `[Verse 1]` / `[Chorus]` markers, set lines-per-slide, and watch the slide grid regenerate.

**Location:** `Sources/Jerusalem/Views/SongEditorView.swift`
**Role:** SwiftUI view — content-authoring editor (song), hosted under the slide-editor window flow

## What it does (plain English)

This is the authoring form for a song. You give it a title and author, set how many lyric lines go on each slide, and type the lyrics in a big text box, wrapping each section header in brackets on its own line (`[Verse 1]`, `[Chorus]`, `[Bridge]`, `[Tag]`). As you type, slides regenerate automatically (debounced so it isn't thrashing the database on every keystroke).

The lyrics block is the **canonical authored source** — `ContentRebuilder` materializes the actual `Slide` rows from it, which the renderer and live navigation then consume. A "Derived slides" section shows the resulting slide/section counts and, if you've manually tweaked slides in the WYSIWYG editor, offers a destructive "Restore auto-generated slides" button.

Per project memory (Phase 8.5), operator-side editing was removed; this view now lives under the dedicated editor window's content rail.

## Swift you'll meet in this file

- **`@Bindable var item: Item`** — makes the SwiftData model bindable so `$item.title` / `$item.linesPerSlide` are two-way field bindings.
- **`@Environment(LiveState.self) private var live`** — Context-style injection of the shared live engine.
- **`@State private var lyrics: String = ""`** — `useState`; a local draft buffer for the lyrics text (kept separate from the model and flushed on debounce / disappear).
- **`@State private var rebuildTask: Task<Void, Never>?`** — a cancellable async task handle for the debounce; `T?` is "T or null".
- **`Form { Section { ... } }`** — a grouped settings-style form; `.formStyle(.grouped)` gives the macOS inset look.
- **`TextField("Title", text: $item.title)`** — a text input bound to a model field.
- **`TextField(..., text: Binding(get:set:))`** — a custom two-way binding that maps `nil ⇄ ""` for the optional subtitle.
- **`Stepper(value: $item.linesPerSlide, in: 1...8)`** — a +/- numeric control clamped to a range.
- **`TextEditor(text: $lyrics)`** — a multi-line text area.
- **`.onChange(of:) { _, newValue in ... }`** — runs a side effect when a value changes (old, new args; `_` ignores old).
- **`.onAppear` / `.onChange(of: item.persistentModelID)` / `.onDisappear`** — lifecycle hooks (mount / item-swap / unmount).
- **`Task { @MainActor in try? await Task.sleep(...) }`** — schedule async work on the main actor; `try?` discards a throwing error as `nil`.
- **`Button(role: .destructive) { ... }`** — a destructive (red) button.

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
