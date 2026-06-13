# `ContentRebuilder.swift`

> The orchestrator that turns an item's *authored* content (song lyrics, sermon body, or Bible reference) into the actual `Slide` + `SlideElement` rows the renderer projects.

**Location:** `Sources/Jerusalem/Content/ContentRebuilder.swift`
**Role:** rebuilder (`@MainActor` namespace)

## What it does (plain English)

There are two representations of every item. The **authored** one is what the operator types — a lyrics block, a sermon title+body, or a Bible reference. The **projected** one is the flat list of `Slide` rows the renderer and live output consume. This file is the bridge: it reads the authored source, runs it through the parsers and the `SlideSplitter`, applies a `Theme`, and replaces the item's slides with freshly built ones.

The public entry point is `rebuild(_:)`, which switches on the item's kind (song/text/bible/media) and dispatches to the right private builder. There are also higher-level "set + rebuild" helpers the editors call directly — `setLyrics`, `setBody`, `setBibleReference` — that update the source *and* regenerate slides in one step.

Crucially, this is the *only* code path that wholesale replaces an item's slides. Editing a single slide by hand (Phase 8) is a separate path — and once any slide is hand-edited (`isManuallyEdited`), the rebuilder **yields**: it stops overwriting, so manual edits are sticky. The `resetToAutoDerived` helper is the escape hatch that clears those flags and re-derives.

## Swift you'll meet in this file

| Swift | JS/TS equivalent |
|---|---|
| `@MainActor enum ContentRebuilder` | a main-thread-pinned namespace of static functions |
| `switch item.kind { case .song: ... }` | `switch` over a discriminated union; the `.song` cases are enum cases |
| `item.modelContext` | the SwiftData DB session that owns the row (`ModelContext?`, nullable) |
| `context?.delete(existing)` | optional chaining — only call `.delete` if context isn't nil |
| `item.slides.contains(where: \.isManuallyEdited)` | `arr.some(s => s.isManuallyEdited)`; `\.x` is a key-path |
| `item.theme ?? Theme.makeDefault()` | nullish coalescing: use the theme, else build a default |
| `(item.bibleTranslation ?? "kjv").lowercased()` | default to "kjv", then lowercase |
| `guard let context = ... else { return }` | early-exit null check that unwraps on success |
| `drafts.enumerated().map { index, draft in ... }` | `drafts.entries()` → `drafts.map((draft, index) => ...)` |
| `item.updatedAt = .now` | `item.updatedAt = new Date()` (`.now` = `Date.now` shorthand) |

## Code walkthrough

**Dispatch by kind.** `rebuild` is the front door; media items have no derived slides so they're a no-op:

```swift
static func rebuild(_ item: Item) {
    switch item.kind {
    case .song:  rebuildSong(item)
    case .text:  rebuildText(item)
    case .bible: rebuildBible(item)
    case .media: return
    }
}
```

**TypeScript equivalent**

```ts
type ItemKind = "song" | "text" | "bible" | "media";

function rebuild(item: Item): void {
  switch (item.kind) {
    case "song":  return rebuildSong(item);
    case "text":  return rebuildText(item);
    case "bible": return rebuildBible(item);
    case "media": return; // no derived slides
  }
}
```

**Swift syntax:**
- `switch item.kind { case .song: ... }` — `item.kind` is an `enum`; `.song` is shorthand for `ItemKind.song` (the type is inferred). Swift `switch` must be *exhaustive* (cover every case) — no `default` needed here because all four are listed. Each `case` doesn't fall through, so no `break`.
- `_ item: Item` — the `_` drops the argument label, so callers write `rebuild(item)` not `rebuild(item: item)`.

**Set-and-rebuild helpers (what editors call).** Each updates the authored source, then rebuilds. For songs, the raw text is parsed into `ParsedSongSection`s and the `SongSection` rows are replaced:

```swift
static func setLyrics(_ text: String, on item: Item) {
    let parsed = SongLyricsParser.parse(text)
    replaceSections(parsed, on: item)
    rebuildSong(item)
}
```

**TypeScript equivalent**

```ts
function setLyrics(text: string, item: Item): void {
  const parsed = SongLyricsParser.parse(text);
  replaceSections(parsed, item);
  rebuildSong(item);
}
```

**Songs.** `rebuildSong` reads the *stored* sections (the source of truth), maps them to value types, and asks the splitter to chunk them:

```swift
let parsed = item.orderedSongSections.map {
    ParsedSongSection(kind: $0.kind, number: $0.number, lyrics: $0.lyrics)
}
let drafts = SlideSplitter.split(songSections: parsed, linesPerSlide: item.linesPerSlide)
materialize(drafts, on: item)
```

**TypeScript equivalent**

```ts
const parsed = item.orderedSongSections.map((s) => ({
  kind: s.kind, number: s.number, lyrics: s.lyrics,
}));
const drafts = SlideSplitter.split({ songSections: parsed, linesPerSlide: item.linesPerSlide });
materialize(drafts, item);
```

**Swift syntax:**
- `.map { ParsedSongSection(kind: $0.kind, ...) }` — a trailing-closure `map` where `$0` is each `SongSection` row. The body constructs a value-type copy (decoupling the pure pipeline from the SwiftData model).
- `SlideSplitter.split(songSections: parsed, linesPerSlide: ...)` — the argument labels `songSections:`/`linesPerSlide:` are part of the call and select the right overload. TS has no labels, so the analog passes a named-options object.

`replaceSections` shows a SwiftData detail: removing rows from the array isn't enough — you must also delete them from the context:

```swift
let context = item.modelContext
for existing in item.songSections { context?.delete(existing) }
item.songSections = parsed.enumerated().map { index, section in
    SongSection(kind: section.kind, number: section.number,
                order: index, lyrics: section.lyrics)
}
```

**TypeScript equivalent**

```ts
const context = item.modelContext;
for (const existing of item.songSections) context?.delete(existing);
// analogy: dropping from the relation array != deleting the row; delete it too.
item.songSections = parsed.map((section, index) => new SongSection({
  kind: section.kind, number: section.number, order: index, lyrics: section.lyrics,
}));
```

**Swift syntax:**
- `context?.delete(existing)` — *optional chaining*: `modelContext` is `ModelContext?`, so `?.` calls `delete` only if it's non-nil (else the whole expression is a no-op). Same as JS `context?.delete(...)`.
- `parsed.enumerated().map { index, section in ... }` — `.enumerated()` pairs each element with its index (like JS `.entries()`), yielding `(index, element)` tuples; the closure destructures them as `index, section`. Note Swift's order is `(index, element)` while JS arrow params from `.map` are `(element, index)` — watch the swap.

**Bible.** `rebuildBible` parses the typed reference, looks up verses, splits, materializes — and writes the canonical form back so the field self-corrects:

```swift
guard let referenceText = item.bibleReference,
      let reference = BibleReferenceParser.parse(referenceText)
else {
    materialize([], on: item)   // unparseable -> clear slides, keep raw text
    return
}
let verses = BibleStore.verses(for: reference, translation: translation, in: context)
let drafts = SlideSplitter.split(bibleVerses: verses, translation: translation)
materialize(drafts, on: item)
item.bibleReference = reference.displayText   // "Psalm 23" -> "Psalms 23"
```

**TypeScript equivalent**

```ts
const referenceText = item.bibleReference;
const reference = referenceText != null ? BibleReferenceParser.parse(referenceText) : null;
if (referenceText == null || reference == null) {
  materialize([], item);        // unparseable -> clear slides, keep raw text
  return;
}
const verses = BibleStore.verses(reference, translation, context);
const drafts = SlideSplitter.split({ bibleVerses: verses, translation });
materialize(drafts, item);
item.bibleReference = displayText(reference); // "Psalm 23" -> "Psalms 23"
```

**Swift syntax:**
- `guard let a, let b else { ... }` — chains *two* optional unwraps in one `guard`. Both `item.bibleReference` and `BibleReferenceParser.parse(...)` must be non-nil to continue; if either is nil, the `else` runs (clear slides, return). Like `if (a == null || b == null) { ...; return; }` but with `a`/`b` then non-nil for the rest of the function.

Note it keeps the user's raw typed string on a parse failure so the editor field doesn't erase itself mid-edit — it only clears the *slides*.

**Sermon/text.** A title slide plus one slide per paragraph:

```swift
let drafts = SlideSplitter.split(
    sermonTitle: item.title,
    body: item.bodyText ?? "",
    linesPerSlide: item.linesPerSlide)
materialize(drafts, on: item)
```

**TypeScript equivalent**

```ts
const drafts = SlideSplitter.split({
  sermonTitle: item.title,
  body: item.bodyText ?? "",
  linesPerSlide: item.linesPerSlide,
});
materialize(drafts, item);
```

**Swift syntax:**
- `item.bodyText ?? ""` — the `??` *nil-coalescing* operator: use `bodyText` if present, else the empty string. Identical to JS `item.bodyText ?? ""`.

**Materialization — the shared tail.** Every builder ends here. This is where the "yield to manual edits" rule lives, plus theming and the actual row creation:

```swift
private static func materialize(_ drafts: [SlideDraft], on item: Item) {
    if item.slides.contains(where: \.isManuallyEdited) { return }   // sticky edits win
    let theme = item.theme ?? Theme.makeDefault()
    if item.theme == nil { item.theme = theme }
    let context = item.modelContext
    for existing in item.slides { context?.delete(existing) }

    let slides: [Slide] = drafts.enumerated().map { index, draft in
        let slide = Slide(order: index, sectionLabel: draft.sectionLabel)
        theme.apply(to: slide)
        let element = SlideElement(kind: .text, order: 0, text: draft.text)
        theme.apply(to: element)
        slide.elements = [element]
        return slide
    }
    item.slides = slides
    item.updatedAt = .now
}
```

**TypeScript equivalent**

```ts
function materialize(drafts: SlideDraft[], item: Item): void {
  if (item.slides.some((s) => s.isManuallyEdited)) return; // sticky edits win
  const theme = item.theme ?? Theme.makeDefault();
  if (item.theme == null) item.theme = theme;
  const context = item.modelContext;
  for (const existing of item.slides) context?.delete(existing);

  const slides: Slide[] = drafts.map((draft, index) => {
    const slide = new Slide({ order: index, sectionLabel: draft.sectionLabel });
    theme.applyToSlide(slide);
    const element = new SlideElement({ kind: "text", order: 0, text: draft.text });
    theme.applyToElement(element);
    slide.elements = [element];
    return slide;
  });
  item.slides = slides;
  item.updatedAt = new Date();
}
```

**Swift syntax:**
- `item.slides.contains(where: \.isManuallyEdited)` — `contains(where:)` is `Array.some`; `\.isManuallyEdited` is a key-path predicate, i.e. `(s) => s.isManuallyEdited`.
- `theme.apply(to: slide)` then `theme.apply(to: element)` — two *overloads* of `apply(to:)` differing by parameter type; Swift picks `Slide` vs `SlideElement` automatically. TS can't overload by arg type at the call site cleanly, so I split them into `applyToSlide`/`applyToElement`.
- `let slides: [Slide] = ...` — explicit type annotation `: [Slide]` (`Slide[]`), here just for clarity since `map` already implies it.
- `.now` — `Date.now`, the current timestamp shorthand.

**Recovery helpers.** `resetToAutoDerived` clears the sticky flags then rebuilds; `hasManualEdits` lets the editor decide whether to show a Reset button; `lyricsText(for:)` re-serializes stored sections back into the editor's text format via `SongLyricsParser.format`.

```swift
static func resetToAutoDerived(_ item: Item) {
    for slide in item.slides { slide.isManuallyEdited = false }
    rebuild(item)
}
```

**TypeScript equivalent**

```ts
function resetToAutoDerived(item: Item): void {
  for (const slide of item.slides) slide.isManuallyEdited = false;
  rebuild(item);
}
```

## How it connects

```
                 setLyrics / setBody / setBibleReference   (editors call these)
                                  │
   SongLyricsParser.parse        │        BibleReferenceParser.parse ──▶ BibleStore.verses
            │                     ▼                  │
      SongSection rows ──▶ rebuild(_:) ──▶ SlideSplitter.split ──▶ [SlideDraft]
                                  │                                      │
                                  ▼                                      ▼
                            materialize  ──▶  Slide + SlideElement rows (themed) ──▶ renderer / LiveState
```

It is the **downstream hub** of the entire Content pipeline: every parser and the store feed it, and it produces the SwiftData rows the renderer/live output consume. Editors debounce the operator's typing, call the `set...` helpers, and re-arm `LiveState` afterward.

## Gotchas / why it matters

- **Source of truth is the authored side.** Songs rebuild from `SongSection` rows; sermons from `bodyText`; Bible from the reference string. Slides are *derived* — never the place to keep canonical content.
- **Idempotent, wholesale replace.** `materialize` deletes all existing slides and rebuilds from scratch every time, so rebuilding twice yields the same result. There's no incremental diffing to get subtly wrong.
- **Sticky manual edits.** The very first line of `materialize` bails out if any slide is `isManuallyEdited`. This is what lets Phase 8 hand-edits survive a re-author. `resetToAutoDerived` is the deliberate way to override that.
- **SwiftData delete dance.** Dropping a row from a relationship array isn't a delete — you must also `context.delete(...)` it. Both `replaceSections` and `materialize` do this.
- **Bible field self-heals but doesn't destroy input.** On success the reference is normalized to `displayText`; on parse failure the raw text is preserved and only the slides are cleared, so the operator can keep typing.
- **`@MainActor`** keeps all this on the main thread, consistent with the app's SwiftData-on-main rule.
