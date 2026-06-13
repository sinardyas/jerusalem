# `PlaylistSlidesView.swift`

> The operator's detail pane when a playlist is selected: every slide in the playlist, in running order, grouped under a sticky header per item.

**Location:** `Sources/Jerusalem/Views/PlaylistSlidesView.swift`
**Role:** SwiftUI view — operator detail pane (grouped slide grid for a whole playlist)

## What it does (plain English)

When the operator selects a *playlist* (not a single item), the middle of the window shows this: one big scrolling grid of slide thumbnails covering the entire playlist, broken into sections — one per item — each with a pinned (sticky) header naming that item. Clicking a thumbnail takes it live; the slide that's currently live gets a red highlight, exactly like the single-item grid.

It's deliberately the playlist twin of `SlideGridView`: it reuses the same `SlideGridCell` for every thumbnail, and the slide ids it produces match the armed flat program, so "click goes live" and "live highlights" behave identically across both views.

## Swift you'll meet in this file

- **`struct PlaylistSlidesView: View { var body: some View }`** — SHAPE: value-type `struct` conforming to `View`, with a `body`. TS analog: `function PlaylistSlidesView(): JSX.Element { return (...) }`; `some View` ≈ `: JSX.Element`.
- **`let playlist: Playlist`** — a non-optional prop; this view is only built when a playlist is actually selected. TS analog: `playlist: Playlist`.
- **`var onActivate: (PersistentIdentifier) -> Void = { _ in }`** — a callback prop with a **default value** (an empty closure, so callers can omit it). SHAPE: `(arg) -> Void = { _ in }` ≈ `(id) => void` defaulting to `() => {}`.
- **`private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 18)]`** — grid track config. `.adaptive` packs as many columns as fit between the min/max widths (like CSS `repeat(auto-fill, minmax(200px, 280px))`).
- **`LazyVGrid(columns:...) { ForEach(...) { Section { ... } header: { ... } } }`** — a virtualized vertical grid (`Lazy` = only builds visible cells); `Section` groups cells with a header; `ForEach` is `.map`. TS analog: a CSS grid with grouped sections.
- **`pinnedViews: [.sectionHeaders]`** — makes section headers stick to the top while scrolling (CSS `position: sticky`).
- **`reduce(0) { $0 + $1.slides.count }`** — like JS `.reduce((acc, g) => acc + g.slides.count, 0)`; `$0`/`$1` are the accumulator and current element.
- **`ContentUnavailableView { ... } description: { ... }`** — the system empty-state placeholder. TS analog: an `<EmptyState>` with `title`/`description` slots.
- **`.background(.bar)`** — the system toolbar/bar material (a translucent backdrop), keeping the header legible over scrolling content.

## Code walkthrough

### Inputs and derived data

```swift
struct PlaylistSlidesView: View {
    let playlist: Playlist
    var liveSlideID: PersistentIdentifier?
    var onActivate: (PersistentIdentifier) -> Void = { _ in }
    var onEdit: (PersistentIdentifier) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 18)]

    private var groups: [LiveState.ProgramGroup] { LiveState.groupedProgram(for: playlist) }
    private var slideCount: Int { groups.reduce(0) { $0 + $1.slides.count } }
```

**TypeScript equivalent**

```tsx
type Props = {
  playlist: Playlist;
  liveSlideID?: PersistentIdentifier | null;
  onActivate?: (id: PersistentIdentifier) => void;  // defaults to () => {}
  onEdit?: (id: PersistentIdentifier) => void;
};

function PlaylistSlidesView({
  playlist,
  liveSlideID,
  onActivate = () => {},
  onEdit = () => {},
}: Props): JSX.Element {
  // analogy: GridItem(.adaptive(...)) -> CSS repeat(auto-fill, minmax(200px, 280px))
  const columns = "repeat(auto-fill, minmax(200px, 280px))";

  // computed properties -> derived values
  const groups = LiveState.groupedProgram(playlist);
  const slideCount = groups.reduce((acc, g) => acc + g.slides.length, 0);
  // ...
}
```

**Swift syntax:**
- `var onActivate: (PersistentIdentifier) -> Void = { _ in }` — a closure-typed property defaulting to an empty closure; `{ _ in }` ignores its single arg. TS analog: `onActivate = () => {}`.
- `private let columns = [...]` — `let` is an immutable constant. TS analog: `const`.
- `private var groups: [...] { ... }` — a computed property (recomputed on access). TS analog: a getter.
- `groups.reduce(0) { $0 + $1.slides.count }` — `.reduce` with a seed of `0`; `$0` = accumulator, `$1` = current group. TS analog: `.reduce((acc, g) => acc + g.slides.length, 0)`.

`groups` asks `LiveState.groupedProgram(for:)` to build the per-item sections (each a title + its slides). The doc comment is explicit that these slide ids **match the armed flat program**, which is what makes click-to-go-live consistent. `slideCount` sums all slides across groups for the subtitle.

### The body — empty state vs. grouped grid

```swift
var body: some View {
    if groups.isEmpty {
        ContentUnavailableView {
            Label("No Slides", systemImage: "rectangle.on.rectangle.slash")
        } description: {
            Text("Add items to this playlist from the sidebar.")
        }
    } else {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18,
                      pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.slides) { slide in
                            SlideGridCell(slide: slide,
                                          isLive: slide.id == liveSlideID,
                                          onActivate: onActivate,
                                          onEdit: onEdit)
                        }
                    } header: {
                        sectionHeader(group.title)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(playlist.name)
        .navigationSubtitle("\(slideCount) slide\(slideCount == 1 ? "" : "s")")
    }
}
```

**TypeScript equivalent**

```tsx
function body(): JSX.Element {
  if (groups.length === 0) {
    return (
      <EmptyState
        title="No Slides"
        icon="rectangle.on.rectangle.slash"
        description="Add items to this playlist from the sidebar."
      />
    );
  }
  return (
    // analogy: ScrollView -> scroll container
    <div className="scroll" data-title={playlist.name}
         data-subtitle={`${slideCount} slide${slideCount === 1 ? "" : "s"}`}>
      {/* analogy: LazyVGrid + pinnedViews:[.sectionHeaders] -> CSS grid with sticky headers */}
      <div style={{ display: "grid", gridTemplateColumns: columns, gap: 18, padding: 20 }}>
        {groups.map(group => (
          <section key={group.id}>
            <div style={{ position: "sticky", top: 0 }}>{sectionHeader(group.title)}</div>
            {group.slides.map(slide => (
              <SlideGridCell
                key={slide.id}
                slide={slide}
                isLive={slide.id === liveSlideID}
                onActivate={onActivate}
                onEdit={onEdit}
              />
            ))}
          </section>
        ))}
      </div>
    </div>
  );
}
```

**Swift syntax:**
- `ForEach(groups) { group in Section { ... } header: { ... } }` — nested trailing closures: the `Section` body builds cells, the `header:` closure builds the pinned header. TS analog: nested `.map` with a header element per section.
- `slide.id == liveSlideID` — comparing an id to the optional `liveSlideID`; `==` works even when one side is `nil`. TS analog: `slide.id === liveSlideID`.
- `LazyVGrid(columns: columns, alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) { ... }` — init args (`columns`, `alignment`, `pinnedViews`) plus a trailing content closure. `[.sectionHeaders]` is an array of enum cases. TS analog: a grid component with a `pinnedViews` prop.

Read it as nested maps: for each `group`, emit a `Section` whose body maps `group.slides` into `SlideGridCell`s and whose header is `sectionHeader(group.title)`. Each cell decides whether it's live with `slide.id == liveSlideID`, and forwards the activate/edit callbacks. `pinnedViews: [.sectionHeaders]` keeps the item titles pinned as you scroll. The title bar shows the playlist name and a pluralized slide count.

### The pinned header

```swift
private func sectionHeader(_ title: String) -> some View {
    HStack {
        Text(title).font(.headline)
        Spacer()
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.bar)
}
```

**TypeScript equivalent**

```tsx
function sectionHeader(title: string): JSX.Element {
  return (
    // analogy: HStack + Spacer -> a row with a flex spacer pushing content left
    <div
      className="row barMaterial"   // .background(.bar) -> translucent bar backdrop
      style={{ width: "100%", padding: "8px 4px", justifyContent: "flex-start" }}
    >
      <Text className="headline">{title}</Text>
      <div style={{ flex: 1 }} />
    </div>
  );
}
```

**Swift syntax:**
- `HStack { Text(...); Spacer() }` — a row; `Spacer()` expands to push siblings apart. TS analog: a flex row with a `flex: 1` spacer.
- `.frame(maxWidth: .infinity, alignment: .leading)` — stretch to full width, content left-aligned. TS analog: `width: 100%; justify-content: flex-start`.
- `.background(.bar)` — the system bar material. TS analog: a translucent backdrop class.

A left-aligned title with a `.bar` material background so it stays readable while slides scroll underneath it.

## How it connects

- Built by `OperatorView.detailPane` when a playlist is selected; receives `playlist`, the current `live.liveSlideID`, and two callbacks wired to `live.goLive(id:)` (activate) and the operator's `openSlideEditor` (edit).
- Sources its sections from **`LiveState.groupedProgram(for:)`**, whose ids align with the armed flat program — so going live and live-highlighting match the single-item `SlideGridView`.
- **Reuses `SlideGridCell`** (defined in `SlideGridView.swift`) for every thumbnail, so playlist slides and single-item slides render identically (including the missing-media warning and section-label badge), and thumbnails go through the shared `SlideRenderer`.

## Gotchas / why it matters

- **Read-only here** — selecting a playlist gives you a navigation/go-live surface; playlist *editing* happens in the sidebar's `PlaylistContentPane`, and slide *editing* opens the separate editor window via `onEdit`.
- **Id alignment is the whole point** — because grouped ids equal the armed program's ids, the operator can click any slide deep in a multi-item playlist and it goes live correctly, with the right thumbnail showing "LIVE".
- **Lazy grid + pinned headers** keep a long playlist (many items, many slides) scrollable and oriented without building every off-screen cell.
- **Shared cell** means one place to fix rendering/warnings, supporting the single-renderer invariant.
