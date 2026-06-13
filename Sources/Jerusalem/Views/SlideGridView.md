# `SlideGridView.swift`

> The operator's main detail grid: rendered thumbnails of the active program's slides — click to go live, right-click to edit.

**Location:** `Sources/Jerusalem/Views/SlideGridView.swift`
**Role:** SwiftUI view — operator detail pane (the slide thumbnail grid) + the shared `SlideGridCell`

## What it does (plain English)

This is the middle of the operator window when a single item (song/Bible/text/media) is selected: a scrolling grid of slide thumbnails. Each thumbnail is the *actual rendered slide* (via the shared renderer), so what you see is what the congregation will see. Clicking a thumbnail takes it live; the live slide gets a red border and a "LIVE" tag; right-clicking opens a menu with "Go Live" and "Edit Slide…" (the latter opens the Phase 8 WYSIWYG editor window).

It's **program-driven**: it takes a `[LiveState.ProgramSlide]` array, not a model, so the same grid works for a single item *or* a whole playlist. The file also defines `SlideGridCell` — the single thumbnail component — which is shared with `PlaylistSlidesView` so both grids look and behave identically (including a yellow "missing media" warning that flags broken file references before Sunday).

## Swift you'll meet in this file

- **`struct SlideGridView: View { var body: some View }`** — SHAPE: value-type `struct` conforming to `View`, with a `body`. TS analog: `function SlideGridView(): JSX.Element { return (...) }`; `some View` ≈ `: JSX.Element`.
- **`let slides: [LiveState.ProgramSlide]`** — the program to display, as immutable value snapshots (not live models). TS analog: `slides: ProgramSlide[]`.
- **`var onActivate: (PersistentIdentifier) -> Void = { _ in }`** — callback prop with a default empty closure; `(id) => void` defaulting to `() => {}`.
- **`GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 18)`** — adaptive grid tracks (CSS `repeat(auto-fill, minmax(200px, 280px))`).
- **`LazyVGrid(columns:...) { ForEach(slides) { ... } }`** — virtualized grid (`Lazy` = builds only visible cells); `ForEach` is `.map`. TS analog: a CSS grid + `.map`.
- **`Button { onActivate(slide.id) } label: { thumbnail }`** — a button whose visible content is the `thumbnail` view; `.buttonStyle(.plain)` strips default chrome. TS analog: `<button onClick={...}>{thumbnail}</button>`.
- **`.contextMenu { ... }`** — the right-click menu. TS analog: a custom context menu.
- **`switch kind { case .slide(let renderable) where ...: }`** — exhaustive switch over an enum with associated values; `where` adds a guard condition to a case. TS analog: `switch` on a tagged union + an `if` inside the case.
- **`@ViewBuilder private func preview(...)`** — lets a function return different views per branch. TS analog: a function returning JSX with `switch`.
- **`.overlay(alignment: .topLeading) { if let label = ... { ... } }`** — layers content (badge / warning icon) at a corner. TS analog: an absolutely-positioned child.
- **`static func hasMissingMedia(...)`** — a `static` (type-level) helper, like a class method in JS. TS analog: a `static` method.
- **`Self.hasMissingMedia(slide)`** — `Self` (capital S) refers to the enclosing type. TS analog: `ClassName.method(...)`.

## Code walkthrough

### `SlideGridView` — the container

```swift
var body: some View {
    if slides.isEmpty {
        ContentUnavailableView {
            Label("No Slides", systemImage: "rectangle.on.rectangle.slash")
        } description: {
            Text("Select a song, Bible passage, or playlist to see its slides.")
        }
    } else {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(slides) { slide in
                    SlideGridCell(slide: slide,
                                  isLive: slide.id == liveSlideID,
                                  onActivate: onActivate,
                                  onEdit: onEdit)
                }
            }
            .padding(20)
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
    }
}
```

**TypeScript equivalent**

```tsx
function body(): JSX.Element {
  if (slides.length === 0) {
    return (
      <EmptyState
        title="No Slides"
        icon="rectangle.on.rectangle.slash"
        description="Select a song, Bible passage, or playlist to see its slides."
      />
    );
  }
  return (
    // analogy: ScrollView -> scroll container; navigationTitle/Subtitle -> window title bits
    <div className="scroll" data-title={title} data-subtitle={subtitle}>
      {/* analogy: LazyVGrid -> CSS grid */}
      <div style={{ display: "grid", gridTemplateColumns: columns, gap: 18, padding: 20 }}>
        {slides.map(slide => (
          <SlideGridCell
            key={slide.id}
            slide={slide}
            isLive={slide.id === liveSlideID}
            onActivate={onActivate}
            onEdit={onEdit}
          />
        ))}
      </div>
    </div>
  );
}
```

**Swift syntax:**
- `ContentUnavailableView { ... } description: { ... }` — the system empty-state placeholder with a label closure and a `description:` closure. TS analog: `<EmptyState title=... description=... />`.
- `ForEach(slides) { slide in ... }` — `.map` with a named param. TS analog: `slides.map(slide => ...)`.
- `slide.id == liveSlideID` — compares against the optional `liveSlideID` (`==` tolerates `nil`). TS analog: `slide.id === liveSlideID`.

Empty → a placeholder; otherwise a lazy grid that maps each `slide` into a `SlideGridCell`, flagging the live one with `slide.id == liveSlideID` and forwarding the two callbacks. The title/subtitle come straight from props (the operator passes the item title and a slide count).

### `SlideGridCell` — one thumbnail (the shared component)

```swift
var body: some View {
    Button { onActivate(slide.id) } label: { thumbnail }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Go Live") { onActivate(slide.id) }
            Button("Edit Slide…") { onEdit(slide.id) }
        }
}
```

**TypeScript equivalent**

```tsx
function SlideGridCell({ slide, isLive, onActivate, onEdit }): JSX.Element {
  return (
    // analogy: Button { action } label: { thumbnail } -> a button whose content is the thumbnail
    <button
      className="plain"
      onClick={() => onActivate(slide.id)}
      onContextMenu={openMenu([                         // .contextMenu
        { label: "Go Live", onClick: () => onActivate(slide.id) },
        { label: "Edit Slide…", onClick: () => onEdit(slide.id) },
      ])}
    >
      {thumbnail}
    </button>
  );
}
```

**Swift syntax:**
- `Button { action } label: { view }` — a button taking the action as the first trailing closure and the visible content as the `label:` closure. TS analog: `<button onClick={action}>{view}</button>`.
- `.buttonStyle(.plain)` — strips default button chrome so the thumbnail shows as-is. TS analog: a `className` resetting button styles.

The whole thumbnail is a borderless button → clicking goes live. The right-click menu offers "Go Live" and "Edit Slide…" (which calls `onEdit`, opening the editor window in the operator).

### The thumbnail visuals

```swift
private var thumbnail: some View {
    VStack(alignment: .leading, spacing: 6) {
        preview(slide.kind)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isLive ? Color.red : Color.gray.opacity(0.35),
                              lineWidth: isLive ? 3 : 1))
            .overlay(alignment: .topLeading) {
                if let label = slide.sectionLabel { /* capsule badge */ }
            }
            .overlay(alignment: .topTrailing) {
                if Self.hasMissingMedia(slide) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("This slide references a file that isn't on disk.")
                }
            }
        if isLive {
            Text("LIVE").font(.caption2.bold()).foregroundStyle(.red)
        }
    }
}
```

**TypeScript equivalent**

```tsx
const thumbnail = (
  // analogy: VStack -> vertical column
  <div className="column" style={{ alignItems: "flex-start", gap: 6 }}>
    <div style={{ position: "relative", borderRadius: 8, overflow: "hidden" }}>
      {preview(slide.kind)}
      {/* border turns red + thicker when live */}
      <div style={{
        position: "absolute", inset: 0, borderRadius: 8,
        border: isLive ? "3px solid red" : "1px solid rgba(128,128,128,0.35)",
      }} />
      {/* .overlay(alignment: .topLeading) -> badge pinned top-left */}
      {slide.sectionLabel && (
        <span style={{ position: "absolute", top: 6, left: 6 }} className="capsule">
          {slide.sectionLabel}
        </span>
      )}
      {/* .overlay(alignment: .topTrailing) -> missing-media warning top-right */}
      {hasMissingMedia(slide) && (
        <Icon
          name="exclamationmark.triangle.fill"
          style={{ position: "absolute", top: 6, right: 6, color: "yellow" }}
          title="This slide references a file that isn't on disk."
        />
      )}
    </div>
    {isLive && <Text className="caption2 bold" style={{ color: "red" }}>LIVE</Text>}
  </div>
);
```

**Swift syntax:**
- `.overlay(alignment: .topLeading) { if let label = slide.sectionLabel { ... } }` — layers a child at a corner; the `if let` includes it only when `sectionLabel` is non-null. TS analog: an absolutely-positioned conditional element.
- `isLive ? Color.red : Color.gray.opacity(0.35)` / `lineWidth: isLive ? 3 : 1` — ternaries driving border color/width. TS analog: conditional inline styles.
- `Self.hasMissingMedia(slide)` — call a `static` method via `Self` (the enclosing type). TS analog: `SlideGridCell.hasMissingMedia(slide)`.

The rendered preview gets a rounded clip and a border that turns **red and thicker when live**. Two corner overlays: a capsule **section-label badge** (e.g. "Verse 1") at top-left when present, and a yellow **missing-media warning** at top-right. A bold red "LIVE" label sits under the thumbnail when it's the live slide.

### Missing-media detection

```swift
private static func hasMissingMedia(_ slide: LiveState.ProgramSlide) -> Bool {
    switch slide.kind {
    case .slide(let renderable): return !MediaAudit.missingFiles(in: renderable).isEmpty
    case .video(let cue):        return !MediaAudit.isPresent(cue)
    }
}
```

**TypeScript equivalent**

```ts
// analogy: static func -> a static method
function hasMissingMedia(slide: ProgramSlide): boolean {
  switch (slide.kind.type) {
    case "slide":
      return MediaAudit.missingFiles(slide.kind.renderable).length > 0;
    case "video":
      return !MediaAudit.isPresent(slide.kind.cue);
  }
}
```

**Swift syntax:**
- `static func hasMissingMedia(_ slide:) -> Bool` — a type-level function (no instance needed); `_` = no external label. TS analog: a `static`/free function.
- `case .slide(let renderable):` — matches the enum case and binds its associated payload to `renderable`. TS analog: destructuring a tagged-union case.
- `!MediaAudit.missingFiles(in: renderable).isEmpty` — `!`-negated emptiness check ("has missing files"). TS analog: `arr.length > 0`.

Delegates to the `MediaAudit` namespace so the UI stays a one-line hook. The comment captures the intent: "so the operator notices on Saturday, not Sunday."

### The preview switch

```swift
@ViewBuilder
private func preview(_ kind: LiveState.ProgramSlide.Kind) -> some View {
    switch kind {
    case .slide(let renderable) where renderable.backgroundVideo != nil:
        // text over black + a film hint (no live video in the grid)
        ZStack { Color.black; RenderableSlideView(renderable: renderable) }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) { Image(systemName: "film") ... }
    case .slide(let renderable):
        RenderableSlideView(renderable: renderable)
    case .video:
        ZStack { Color.black; Image(systemName: "film").font(.largeTitle) ... }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}
```

**TypeScript equivalent**

```tsx
// analogy: @ViewBuilder func -> a function returning JSX
function preview(kind: ProgramSlideKind): JSX.Element {
  switch (kind.type) {
    case "slide":
      if (kind.renderable.backgroundVideo != null) {
        // motion-background slide: text over black + a film hint (no live video in the grid)
        return (
          <div style={{ position: "relative", aspectRatio: "16 / 9", background: "black" }}>
            <RenderableSlideView renderable={kind.renderable} />
            <Icon name="film" style={{ position: "absolute", bottom: 5, right: 5 }} />
          </div>
        );
      }
      return <RenderableSlideView renderable={kind.renderable} />;
    case "video":
      return (
        <div style={{ position: "relative", aspectRatio: "16 / 9", background: "black" }}>
          <Icon name="film" className="largeTitle" />
        </div>
      );
  }
}
```

**Swift syntax:**
- `case .slide(let renderable) where renderable.backgroundVideo != nil:` — `where` adds a guard to a case, so the *same* `.slide` case is split into two: one with a motion background, one without. TS analog: an `if` inside the `case` branch.
- `ZStack { Color.black; RenderableSlideView(...) }` — layered children (black behind, slide in front). TS analog: absolutely-positioned siblings.
- `.aspectRatio(16.0 / 9.0, contentMode: .fit)` — keep a 16:9 box. TS analog: `aspect-ratio: 16 / 9`.

Three thumbnail flavors: a **motion-background slide** shows its text over black plus a film hint (no live video in the grid, to keep it light); a **plain slide** renders normally via `RenderableSlideView`; a **pure video** clip shows a black tile with a film glyph. The `where renderable.backgroundVideo != nil` guard distinguishes the first two `.slide` cases.

## How it connects

- Built by `OperatorView.slideGrid` for a single selected item; receives the armed `program`, `live.liveSlideID`, and callbacks wired to `live.goLive(id:)` and the operator's `openSlideEditor`.
- **`SlideGridCell` is shared** with `PlaylistSlidesView`, so single-item and playlist grids render thumbnails identically.
- Thumbnails go through the shared rendering views (`RenderableSlideView`), i.e. the single `SlideRenderer` path — the same image pipeline as the live output, guaranteeing the preview matches the audience screen.
- Missing-media checks use the `MediaAudit` namespace.

## Gotchas / why it matters

- **Program-driven, model-free** — operating on `LiveState.ProgramSlide` value snapshots is what lets one grid serve both items and playlists, and keeps live output decoupled from in-progress edits.
- **One shared `SlideGridCell`** upholds the single-renderer invariant: fix or restyle thumbnails in exactly one place.
- **Missing-media warning is a reliability feature**, not decoration — it surfaces broken file references during setup, supporting "never fail on Sunday morning."
- **Click = go live** — every thumbnail is a live trigger, so the operator drives the service entirely from this grid (or the keyboard). Editing is intentionally one extra step away (right-click → "Edit Slide…").
