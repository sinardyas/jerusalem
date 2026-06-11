# `LiveState.swift`

> The single source of truth for what the audience currently sees and which slide is "live" — held as immutable value snapshots, never live database models.

**Location:** `Sources/Jerusalem/Live/LiveState.swift`
**Role:** observable store

## What it does (plain English)

`LiveState` is the brain of the live show. It holds the *program* (the ordered list of things to project), tracks which one is currently showing, and resolves all of that down to a single `content` value that the output window renders. Think of it as a small global store (like a React/MobX store) that the operator UI and the audience window both read.

The crucial idea is **arm vs. go-live**. You can *arm* a program (load a whole playlist or song) without changing a single pixel on the audience screen — the output stays whatever it was. Only when the operator presses a navigation key or clicks a slide (`next()`, `goLive(id:)`) does the program actually *start* and content appear. This is what lets the operator prepare the next song while the current one is still on screen.

It also owns the **panic states** — Black, Clear (background only, text stripped), and Logo — which the operator can slam on instantly with a key. And because `content` only ever holds value-type snapshots (`RenderableSlide` / `VideoCue`), editing the underlying SwiftData model in another window cannot leak onto the audience screen mid-service.

## Swift you'll meet in this file

- `@MainActor` — every method here is forced by the compiler to run on the main/UI thread (the projector output is UI, so this is required).
- `@Observable class` — a shared store; when a view reads `live.content`, that view auto-subscribes and re-renders when it changes (like a React store).
- `final class` — a reference type (shared, not copied) that can't be subclassed.
- `struct` — a value type, copied on assignment. `ProgramSlide`, `ProgramGroup`, `VideoCue`, `RenderableSlide` are structs — that's *why* snapshots are safe.
- `enum Panic` / `enum Content` / `enum Kind` — TS-style unions. Cases that carry data (`.slide(RenderableSlide)`, `.video(VideoCue)`) are discriminated unions; `switch` over them is exhaustive.
- `let` = `const`, `var` = `let` (reassignable).
- `private(set) var` — readable everywhere, writable only inside this class (like a TS `readonly` public getter with a private setter).
- `T?` = `T | null`; `if case .slide(let renderable) = kind` binds the associated value (pattern matching).
- `PersistentIdentifier` — SwiftData's stable ID for a model row, used here purely as identity (not the live object).
- Closures `{ $0.id == id }` = arrow functions; `$0` is the implicit first argument.

## Code walkthrough

The store exposes four nested value types and two enums.

`ProgramSlide` is one navigable step — either a rendered slide or a video clip — plus its identity and a section label:

```swift
struct ProgramSlide: Identifiable, Equatable {
    let id: PersistentIdentifier
    let kind: Kind
    let sectionLabel: String?

    enum Kind: Equatable {
        case slide(RenderableSlide)
        case video(VideoCue)
    }
}
```

The `renderable` and `videoCue` computed properties just unwrap the union — they return `nil` when the case doesn't match (like a type guard returning `null`).

`ProgramGroup` is a titled cluster of slides (one playlist entry) used to draw the grouped grid. It's keyed on the `PlaylistEntry` id, not the item id, so the *same* song appearing twice in a playlist forms *two* distinct groups.

`Content` is what the output actually shows — `.empty`, `.black`, `.logo`, `.slide(...)`, or `.video(...)`:

```swift
enum Content: Equatable, Hashable { case empty, black, logo, slide(RenderableSlide), video(VideoCue) }
```

The state fields are all `private(set)` so only `LiveState`'s own methods can change them:

```swift
private(set) var content: Content = .empty
private(set) var program: [ProgramSlide] = []
private(set) var index: Int = 0
private(set) var started: Bool = false
private(set) var panic: Panic = .none
var transition: TransitionStyle = .fade
```

`liveSlideID` returns the id of the currently-live slide *only* when the show is started, not panicked, and the index is valid — otherwise `nil` (used to highlight the live cell in the grid). `nextProgramSlide` peeks at the slide a "next" press will reveal (for the inspector's preview); note that before the show starts it points at index `0`, after starting at `index + 1`.

**Program control** is the heart of the file:

- `arm(_:)` loads a program but sets `started = false` — so `recompute()` falls through to `.empty` and the output doesn't change.
- `goLive(id:)` jumps straight to a slide by id and sets `started = true`.
- `next()` has three branches: if panicked, a nav key *resumes* (clears panic); if not yet started, the first press starts at index 0; otherwise it advances, clamped to the last slide.
- `previous()` mirrors that (and is a no-op before the show starts).
- `setPanic(_:)` *toggles* — pressing Black again un-blacks.
- `clear()` wipes the whole program.

Every mutator ends by calling `recompute()`, which is the single place that derives `content` from the state:

```swift
private func recompute() {
    switch panic {
    case .black:
        content = .black
    case .logo:
        content = .logo
    case .clear where started && program.indices.contains(index):
        content = clearedContent(of: program[index])
    case .none where started && program.indices.contains(index):
        content = liveContent(of: program[index])
    default:
        content = .empty
    }
}
```

`clearedContent(of:)` is a nice touch: "Clear" keeps the slide's background (color/video) but rebuilds the `RenderableSlide` with an empty `elements` array — so the text vanishes but the backdrop stays.

**Building programs** are the `static` factory functions that turn database models into value snapshots:

- `programSlides(for item: Item)` handles media items specially: it reads the filename, asks `MediaImport.kind(...)` whether it's video or image, and builds a `VideoCue` or an image-backed `RenderableSlide`. For normal items it maps each ordered slide through `RenderableSlide($0)`.
- `programSlides(for playlist:)` flattens every entry's item into one running list.
- `groupedProgram(for:)` produces the titled groups. The doc comment guarantees the grouped and flat versions share slide identities, so click-to-go-live and live-highlight stay aligned.

Finally, `TransitionStyle` is a tiny string-backed enum (`cut` / `fade`) with a display label, used by the output's animation.

## How it connects

`LiveState` is created once in `JerusalemApp` and injected via `.environment(...)`. The operator window calls `arm`, `next`, `previous`, `goLive`, `setPanic`, `clear` in response to keys/clicks. `OutputController` holds a reference to it and hands it to `OutputView`, which reads `live.content` and renders it through the shared `SlideView` / `SlideRenderer` (for slides) or `VideoPlayerView` (for clips). The factory functions consume `Item` / `Playlist` SwiftData models but emit only value snapshots.

## Gotchas / why it matters

- **Arm vs. go-live is the safety mechanism.** Loading the next song never touches the screen; only an explicit operator action does. This is "never fail on Sunday" by design.
- **Value snapshots, not models.** `content` holds `RenderableSlide` / `VideoCue` structs. Even if someone edits the original song in another window, the live screen can't change until the operator re-arms or navigates. Never push a `@Model` object into here.
- **`recompute()` is the only writer of `content`.** Keep it that way — every state change funnels through one resolver, so the output can never be left in an inconsistent state.
- **Panic toggles and nav-resumes-from-panic.** A flustered operator can hit Black, then press the arrow key and the show resumes exactly where it was — no lost place.
- **`@MainActor`** guarantees all of this runs on the UI thread, matching the renderer's main-thread requirement.
