# `BibleEditorView.swift`

> Phase 7 Bible editor: type a scripture reference, pick a translation, and watch the slides regenerate from the bundled scripture store.

**Location:** `Sources/Jerusalem/Views/BibleEditorView.swift`
**Role:** SwiftUI view — content-authoring editor (Bible), hosted under the slide-editor window flow

## What it does (plain English)

This is the authoring form for a Bible passage. You type a reference like `John 3:16-18`, pick a translation, and the app looks it up in the bundled offline scripture store and regenerates the slides. The reference field is **sticky and forgiving**: if you've typed something it can't yet parse, it shows a soft orange warning instead of clearing your input, so you can finish typing. Empty or unknown references clear the slide grid so the operator sees the unknown state rather than stale verses.

A footer line gives live feedback (couldn't parse / not in the bundled translation / which starter passages are available), and a "Derived slides" section shows the slide count, the parsed lookup, and a "Restore auto-generated slides" button if slides were manually edited.

Per project memory (Phase 8.5), operator-side editing was removed; this view now lives under the dedicated editor window's content rail.

## Swift you'll meet in this file

- **`@Bindable var item: Item`** — bindable SwiftData model (`$item.title`).
- **`@Environment(LiveState.self) private var live`** — injected shared live engine.
- **`@State private var referenceDraft` / `@State private var translation`** — `useState` local drafts; the reference stays in the field even when unparseable.
- **`@State private var rebuildTask: Task<Void, Never>?`** — cancellable debounce handle.
- **`private var parsedReference: BibleReference?`** — a computed optional; `BibleReferenceParser.parse(...)` returns `nil` when the text can't be parsed.
- **`Form { Section { ... } header: { } footer: { } }`** — a grouped form with per-section header and footer slots.
- **`Picker("Translation", selection: $translation) { ForEach(translations) { Text($0.displayName).tag($0.id) } }`** — a dropdown; `.map` over translations, `.tag` carries each option's id.
- **`LabeledContent("Slides", value: "...")`** — a label/value row.
- **`@ViewBuilder private var footerText: some View`** — lets the footer pick one of several `Text`s via `if`/`else`.
- **`.onChange(of:) { _, _ in ... }` / `.onAppear` / `.onDisappear`** — lifecycle + change hooks.
- **`(item.bibleTranslation ?? translations.first?.id ?? "kjv").lowercased()`** — chained `??` nullish-coalescing fallbacks.

## Code walkthrough

### The reference + translation inputs

```swift
Section {
    TextField("Title", text: $item.title)
    TextField("Reference (e.g. John 3:16-18)", text: $referenceDraft)
        .textFieldStyle(.roundedBorder)
        .onChange(of: referenceDraft) { _, _ in scheduleRebuild() }
    Picker("Translation", selection: $translation) {
        ForEach(translations) { t in
            Text(t.displayName).tag(t.id)
        }
    }
    .onChange(of: translation) { _, _ in
        scheduleRebuild(immediate: true)
    }
} header: {
    Text("Bible")
} footer: {
    footerText
}
```

The reference field binds to the local `referenceDraft` (not the model directly), and each keystroke calls `scheduleRebuild()` (debounced). Changing the **translation** calls `scheduleRebuild(immediate: true)` — translation changes apply right away, with no debounce. `translations` comes from `BibleSeeder.bundledTranslations()`.

### Derived slides + reset

```swift
Section("Derived slides") {
    LabeledContent("Slides", value: "\(item.orderedSlides.count)")
    if let parsed = parsedReference {
        LabeledContent("Lookup", value: parsed.displayText)
    }
    if ContentRebuilder.hasManualEdits(item) {
        Button(role: .destructive) {
            ContentRebuilder.resetToAutoDerived(item)
            live.arm(LiveState.programSlides(for: item))
        } label: {
            Label("Restore auto-generated slides", systemImage: "arrow.uturn.backward")
        }
    }
}
```

Shows the slide count and, when the reference parses, the canonical "Lookup" text. The reset button (only when manual edits exist) re-derives slides from the reference and re-arms.

### The footer feedback

```swift
@ViewBuilder private var footerText: some View {
    if !referenceDraft.isEmpty && parsedReference == nil {
        Text("Couldn't parse that reference. Try `John 3:16` or `Psalm 23`.")
            .font(.caption).foregroundStyle(.orange)
    } else if let parsed = parsedReference, item.orderedSlides.isEmpty {
        Text("`\(parsed.displayText)` isn't in the bundled \(translation.uppercased()) yet.")
            ...
    } else {
        Text("Bundled translations cover only the Phase 7 starter passages ...")
            ...
    }
}
```

Three states: an **orange parse warning** (typed but unparseable), a **not-in-bundle note** (parsed but no slides), or a default hint listing the starter passages. The doc comment notes it always renders *some* `Text` because SwiftUI dislikes empty top-level `if` branches in a view builder.

### Lifecycle — load and flush drafts

```swift
.onAppear {
    referenceDraft = item.bibleReference ?? ""
    translation = (item.bibleTranslation ?? translations.first?.id ?? "kjv").lowercased()
}
.onChange(of: item.persistentModelID) { _, _ in
    referenceDraft = item.bibleReference ?? ""
    translation = (item.bibleTranslation ?? translations.first?.id ?? "kjv").lowercased()
}
.onDisappear {
    rebuildTask?.cancel()
    ContentRebuilder.setBibleReference(referenceDraft, translation: translation, on: item)
}
```

Drafts load from the model on appear (and item-swap). On disappear it cancels the debounce and **flushes** the reference + translation via `ContentRebuilder.setBibleReference`, so a partly-typed reference is persisted.

### The debounce (with immediate path)

```swift
private func scheduleRebuild(immediate: Bool = false) {
    rebuildTask?.cancel()
    if immediate {
        ContentRebuilder.setBibleReference(referenceDraft, translation: translation, on: item)
        live.arm(LiveState.programSlides(for: item))
        return
    }
    rebuildTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        ContentRebuilder.setBibleReference(referenceDraft, translation: translation, on: item)
        live.arm(LiveState.programSlides(for: item))
    }
}
```

Typing in the reference takes the debounced (350 ms) path; switching translation takes the `immediate` path that writes and re-arms synchronously. Both end by calling `ContentRebuilder.setBibleReference` and re-arming the program.

## How it connects

- Looks up scripture through **`BibleReferenceParser.parse`** (for the live "Lookup" display) and persists/regenerates via the **`ContentRebuilder.setBibleReference`** namespace, which pulls verses from the bundled offline store seeded by `BibleSeeder`.
- Re-arms the live program with **`live.arm(LiveState.programSlides(for: item))`** after edits (no audience change until the operator acts).
- Bound to the `@Bindable` `Item`; SwiftData autosaves.

## Gotchas / why it matters

- **Sticky, forgiving reference field** — keeping unparseable input in the draft (with an orange warning) is deliberate UX so half-typed references don't vanish mid-edit.
- **Translation change is immediate, reference is debounced** — switching translation should re-render at once; typing a reference shouldn't thrash the parser/store.
- **Offline-only and limited** — the bundled translations cover just the Phase 7 starter passages (John 3, Psalm 23, Rom 8:28, Phil 4:13); fuller Bibles come from `Tools/build-bible-db`. The footer makes this explicit so the operator isn't surprised on Sunday.
- **`.onDisappear` flush** persists the last reference/translation even if the debounce hadn't fired.
- **Re-arm vs. go-live** — edits re-arm only; the value-snapshot separation keeps the audience screen stable until the operator advances.
