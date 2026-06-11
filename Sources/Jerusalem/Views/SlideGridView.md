# `SlideGridView.swift`

> The operator's main detail grid: rendered thumbnails of the active program's slides — click to go live, right-click to edit.

**Location:** `Sources/Jerusalem/Views/SlideGridView.swift`
**Role:** SwiftUI view — operator detail pane (the slide thumbnail grid) + the shared `SlideGridCell`

## What it does (plain English)

This is the middle of the operator window when a single item (song/Bible/text/media) is selected: a scrolling grid of slide thumbnails. Each thumbnail is the *actual rendered slide* (via the shared renderer), so what you see is what the congregation will see. Clicking a thumbnail takes it live; the live slide gets a red border and a "LIVE" tag; right-clicking opens a menu with "Go Live" and "Edit Slide…" (the latter opens the Phase 8 WYSIWYG editor window).

It's **program-driven**: it takes a `[LiveState.ProgramSlide]` array, not a model, so the same grid works for a single item *or* a whole playlist. The file also defines `SlideGridCell` — the single thumbnail component — which is shared with `PlaylistSlidesView` so both grids look and behave identically (including a yellow "missing media" warning that flags broken file references before Sunday).

## Swift you'll meet in this file

- **`let slides: [LiveState.ProgramSlide]`** — the program to display, as immutable value snapshots (not live models).
- **`var onActivate: (PersistentIdentifier) -> Void = { _ in }`** — callback prop with a default empty closure; `(id) => void`.
- **`GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 18)`** — adaptive grid tracks (CSS `repeat(auto-fill, minmax(200px, 280px))`).
- **`LazyVGrid(columns:...) { ForEach(slides) { ... } }`** — virtualized grid; `ForEach` is `.map`.
- **`Button { onActivate(slide.id) } label: { thumbnail }`** — a button whose visible content is the `thumbnail` view; `.buttonStyle(.plain)` strips default chrome.
- **`.contextMenu { ... }`** — the right-click menu.
- **`switch kind { case .slide(let renderable) where ...: }`** — exhaustive switch over an enum with associated values; `where` adds a guard condition to a case.
- **`@ViewBuilder private func preview(...)`** — lets a function return different views per branch.
- **`.overlay(alignment: .topLeading) { if let label = ... { ... } }`** — layers content (badge / warning icon) at a corner.
- **`static func hasMissingMedia(...)`** — a `static` (type-level) helper, like a class method in JS.
- **`Self.hasMissingMedia(slide)`** — `Self` (capital S) refers to the enclosing type.

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
