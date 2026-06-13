# `BibleEditorView.swift`

> Phase 7 Bible editor: type a scripture reference, pick a translation, and watch the slides regenerate from the bundled scripture store.

**Location:** `Sources/Jerusalem/Views/BibleEditorView.swift`
**Role:** SwiftUI view — content-authoring editor (Bible), hosted under the slide-editor window flow

## What it does (plain English)

This is the authoring form for a Bible passage. You type a reference like `John 3:16-18`, pick a translation, and the app looks it up in the bundled offline scripture store and regenerates the slides. The reference field is **sticky and forgiving**: if you've typed something it can't yet parse, it shows a soft orange warning instead of clearing your input, so you can finish typing. Empty or unknown references clear the slide grid so the operator sees the unknown state rather than stale verses.

A footer line gives live feedback (couldn't parse / not in the bundled translation / which starter passages are available), and a "Derived slides" section shows the slide count, the parsed lookup, and a "Restore auto-generated slides" button if slides were manually edited.

Per project memory (Phase 8.5), operator-side editing was removed; this view now lives under the dedicated editor window's content rail.

## Swift you'll meet in this file

- **`struct BibleEditorView: View { var body: some View }`** — SHAPE: a value-type `struct` conforming to `View`, with a `body` computed property. TS analog: `function BibleEditorView(): JSX.Element { return (...) }`. `some View` = "returns some concrete View, type hidden" ≈ `: JSX.Element`.
- **`@Bindable var item: Item`** — bindable SwiftData model so `$item.title` is a two-way binding. TS analog: a model object plus a `setItem`/two-way prop you read and write.
- **`@Environment(LiveState.self) private var live`** — injected shared live engine. TS analog: `const live = useContext(LiveStateContext)`.
- **`@State private var referenceDraft` / `@State private var translation`** — `useState` local drafts; the reference stays in the field even when unparseable. TS analog: `const [referenceDraft, setReferenceDraft] = useState("")`.
- **`@State private var rebuildTask: Task<Void, Never>?`** — cancellable debounce handle. SHAPE: `T?` = "T or null". TS analog: `let rebuildTask: Promise<void> | null` you can cancel.
- **`private var parsedReference: BibleReference?`** — a computed optional; `BibleReferenceParser.parse(...)` returns `nil` when the text can't be parsed. TS analog: `get parsedReference(): BibleReference | null`.
- **`Form { Section { ... } header: { } footer: { } }`** — a grouped form with per-section header and footer slots. SHAPE: trailing-closure container with extra labeled closure args. TS analog: `<Form><Section header={...} footer={...}>...</Section></Form>`.
- **`Picker("Translation", selection: $translation) { ForEach(translations) { Text($0.displayName).tag($0.id) } }`** — a dropdown; `ForEach` is `.map` over translations, `.tag` carries each option's id. TS analog: `<select>{translations.map(t => <option value={t.id}>{t.displayName}</option>)}</select>`.
- **`LabeledContent("Slides", value: "...")`** — a label/value row. TS analog: `<LabeledRow label="Slides" value="..." />`.
- **`@ViewBuilder private var footerText: some View`** — lets the footer pick one of several `Text`s via `if`/`else`. SHAPE: `@ViewBuilder` makes a property able to branch and still return one view. TS analog: a function returning JSX with `if`/`else`.
- **`(item.bibleTranslation ?? translations.first?.id ?? "kjv").lowercased()`** — chained `??` nullish-coalescing fallbacks; `?.` is optional chaining. TS analog: `(item.bibleTranslation ?? translations[0]?.id ?? "kjv").toLowerCase()`.

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

**TypeScript equivalent**

```tsx
<Section
  header={<Text>Bible</Text>}
  footer={footerText}
>
  <input value={item.title} onChange={e => setItemTitle(e.target.value)} />
  <input
    className="roundedBorder"
    value={referenceDraft}
    onChange={e => { setReferenceDraft(e.target.value); scheduleRebuild(); }}
  />
  {/* analogy: Picker -> <select>; .tag carries each option's value */}
  <select
    value={translation}
    onChange={e => { setTranslation(e.target.value); scheduleRebuild({ immediate: true }); }}
  >
    {translations.map(t => (
      <option key={t.id} value={t.id}>{t.displayName}</option>
    ))}
  </select>
</Section>
```

**Swift syntax:**
- `$item.title` / `$referenceDraft` — the `$` prefix turns a state value (or `@Bindable` field) into a two-way **Binding**, like passing `value` + `onChange` as one prop.
- `.onChange(of:) { _, _ in ... }` — runs a side effect when a value changes; the two args are `(oldValue, newValue)` and `_` ignores both. TS analog: `useEffect(..., [value])` or an inline `onChange` handler.
- `{ t in ... }` — a closure with a named param `t`; the `t.displayName` body builds each row. TS analog: `t => ...`.

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

**TypeScript equivalent**

```tsx
<Section title="Derived slides">
  <LabeledRow label="Slides" value={`${item.orderedSlides.length}`} />
  {parsedReference && (
    <LabeledRow label="Lookup" value={parsedReference.displayText} />
  )}
  {ContentRebuilder.hasManualEdits(item) && (
    <button
      className="destructive"
      onClick={() => {
        ContentRebuilder.resetToAutoDerived(item);
        live.arm(LiveState.programSlides(item));
      }}
    >
      {/* analogy: Label = icon + text */}
      <Icon name="arrow.uturn.backward" /> Restore auto-generated slides
    </button>
  )}
</Section>
```

**Swift syntax:**
- `if let parsed = parsedReference { ... }` — optional binding: runs the branch only when the optional is non-null, binding the unwrapped value to `parsed`. TS analog: `if (parsedReference) { const parsed = parsedReference; ... }` or `&&`.
- `"\(item.orderedSlides.count)"` — string interpolation. TS analog: `` `${item.orderedSlides.length}` ``.
- `Button(role: .destructive) { action } label: { view }` — trailing-closure button; `role: .destructive` is a semantic hint that styles it red. TS analog: `<button className="destructive" onClick={...}>{label}</button>`.

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

**TypeScript equivalent**

```tsx
// analogy: a @ViewBuilder property -> a function returning JSX
function footerText(): JSX.Element {
  if (referenceDraft !== "" && parsedReference == null) {
    return (
      <Text className="caption" style={{ color: "orange" }}>
        Couldn't parse that reference. Try `John 3:16` or `Psalm 23`.
      </Text>
    );
  } else if (parsedReference && item.orderedSlides.length === 0) {
    return (
      <Text className="caption secondary">
        {`\`${parsedReference.displayText}\` isn't in the bundled ${translation.toUpperCase()} yet.`}
      </Text>
    );
  } else {
    return (
      <Text className="caption secondary">
        Bundled translations cover only the Phase 7 starter passages ...
      </Text>
    );
  }
}
```

**Swift syntax:**
- `else if let parsed = parsedReference, item.orderedSlides.isEmpty` — an optional binding *and* a boolean condition chained with a comma (both must pass). TS analog: `else if (parsedReference && item.orderedSlides.length === 0)`.
- `parsedReference == nil` — `nil` is Swift's `null`/`undefined`. TS analog: `== null`.

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

**TypeScript equivalent**

```tsx
// analogy: .onAppear / .onChange(of: item.id) / .onDisappear -> useEffect
useEffect(() => {
  // .onAppear AND .onChange(of: item.persistentModelID): re-sync when item changes
  setReferenceDraft(item.bibleReference ?? "");
  setTranslation((item.bibleTranslation ?? translations[0]?.id ?? "kjv").toLowerCase());

  return () => {
    // .onDisappear cleanup: cancel debounce + flush the draft
    rebuildTask?.cancel();
    ContentRebuilder.setBibleReference(referenceDraft, translation, item);
  };
}, [item.persistentModelID]);
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

**TypeScript equivalent**

```ts
function scheduleRebuild({ immediate = false }: { immediate?: boolean } = {}): void {
  rebuildTask?.cancel();
  if (immediate) {
    ContentRebuilder.setBibleReference(referenceDraft, translation, item);
    live.arm(LiveState.programSlides(item));
    return;
  }
  // analogy: Task { @MainActor in ... } -> an async run on the main thread
  rebuildTask = runCancellable(async () => {
    await sleep(350);
    if (rebuildTask?.isCancelled) return;
    ContentRebuilder.setBibleReference(referenceDraft, translation, item);
    live.arm(LiveState.programSlides(item));
  });
}
```

**Swift syntax:**
- `func scheduleRebuild(immediate: Bool = false)` — `immediate:` is a labeled parameter with a default value. TS analog: an options object with a default (`{ immediate = false } = {}`).
- `Task { @MainActor in ... }` — schedules async work pinned to the main thread/actor. TS analog: `(async () => { ... })()` (JS is already single-threaded).
- `try? await Task.sleep(...)` — `await` an async call; `try?` discards a thrown error as `nil`. TS analog: `await sleep(...)` wrapped so a throw is swallowed.
- `guard !Task.isCancelled else { return }` — early-exit guard: if the condition fails, run the `else` and bail. TS analog: `if (cancelled) return;`.

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
