# `LiveState.swift`

> The single source of truth for what the audience currently sees and which slide is "live" — held as immutable value snapshots, never live database models.

**Location:** `Sources/Jerusalem/Live/LiveState.swift`
**Role:** observable store

## What it does (plain English)

`LiveState` is the brain of the live show. It holds the *program* (the ordered list of things to project), tracks which one is currently showing, and resolves all of that down to a single `content` value that the output window renders. Think of it as a small global store (like a React/MobX store) that the operator UI and the audience window both read.

The crucial idea is **arm vs. go-live**. You can *arm* a program (load a whole playlist or song) without changing a single pixel on the audience screen — the output stays whatever it was. Only when the operator presses a navigation key or clicks a slide (`next()`, `goLive(id:)`) does the program actually *start* and content appear. This is what lets the operator prepare the next song while the current one is still on screen.

It also owns the **panic states** — Black, Clear (background only, text stripped), and Logo — which the operator can slam on instantly with a key. And because `content` only ever holds value-type snapshots (`RenderableSlide` / `VideoCue`), editing the underlying SwiftData model in another window cannot leak onto the audience screen mid-service.

## Swift you'll meet in this file

- `@MainActor` — pins the whole class to the main/UI thread (`// must run on the main/UI thread`). In TS there's only one thread, so this has no direct analog — it's a compiler-enforced "never call this off the UI thread."
- `@Observable class` — a shared store; reading `live.content` in a view auto-subscribes it. Shape: `@observable class X { ... }` → a MobX-style store where views auto-re-render on field changes.
- `final class` — a reference type (shared, not copied) that can't be subclassed → `class X` with no `extends`.
- `struct` — a value type, *copied* on assignment → a TS `interface` / `readonly` data object. `ProgramSlide`, `ProgramGroup`, `VideoCue`, `RenderableSlide` are structs — that's *why* snapshots are safe.
- `enum Panic` / `enum Content` / `enum Kind` — cases that carry data (`.slide(RenderableSlide)`) are discriminated unions → `type Content = { kind: "slide", ... } | { kind: "black" } | ...`; `switch` over them is exhaustive.
- `let` = `const`, `var` = `let` (reassignable).
- `private(set) var` — readable everywhere, writable only inside this class → a public `readonly` getter backed by a private setter.
- `T?` = `T | null`; `if case .slide(let renderable) = kind` binds the associated value → `if (kind.tag === "slide") { const renderable = kind.value }`.
- `guard … else { return }` — early-exit-or-bind → `if (!cond) return;`.
- `PersistentIdentifier` — SwiftData's stable ID for a model row, used here purely as identity (not the live object) → a `string`/branded id.
- Closures `{ $0.id == id }` = arrow functions; `$0` is the implicit first argument → `x => x.id === id`.
- Computed property `var hasProgram: Bool { !program.isEmpty }` — a getter with no stored backing → `get hasProgram() { return this.program.length > 0 }`.

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

**TypeScript equivalent**

```ts
type ProgramSlideKind =
  | { kind: "slide"; renderable: RenderableSlide }
  | { kind: "video"; cue: VideoCue };

interface ProgramSlide {
  readonly id: PersistentIdentifier;   // stable row id, used only as identity
  readonly kind: ProgramSlideKind;
  readonly sectionLabel: string | null;
}

// the computed unwrap-helpers: like type guards that return null on mismatch
function renderable(s: ProgramSlide): RenderableSlide | null {
  return s.kind.kind === "slide" ? s.kind.renderable : null;
}
function videoCue(s: ProgramSlide): VideoCue | null {
  return s.kind.kind === "video" ? s.kind.cue : null;
}
```

**Swift syntax:**
- `enum Kind { case slide(RenderableSlide); case video(VideoCue) }` — an `enum` *with associated values* is a discriminated union. Each case is a `kind` tag that can carry a payload. Maps to a TS union of `{ kind: "...", ... }` objects.
- `if case .slide(let renderable) = kind { ... }` — pattern-matches one case and binds its payload in a single statement → `if (kind.kind === "slide") { const renderable = kind.renderable; ... }`.
- `Identifiable`/`Equatable` — protocol conformances (like `implements`); `Identifiable` means "has an `id`" so SwiftUI lists can track it, `Equatable` gives value `==`.

The `renderable` and `videoCue` computed properties just unwrap the union — they return `nil` when the case doesn't match (like a type guard returning `null`).

`ProgramGroup` is a titled cluster of slides (one playlist entry) used to draw the grouped grid. It's keyed on the `PlaylistEntry` id, not the item id, so the *same* song appearing twice in a playlist forms *two* distinct groups.

`Content` is what the output actually shows — `.empty`, `.black`, `.logo`, `.slide(...)`, or `.video(...)`:

```swift
enum Content: Equatable, Hashable { case empty, black, logo, slide(RenderableSlide), video(VideoCue) }
```

**TypeScript equivalent**

```ts
// discriminated union of everything the output can display
type Content =
  | { kind: "empty" }
  | { kind: "black" }
  | { kind: "logo" }
  | { kind: "slide"; slide: RenderableSlide }
  | { kind: "video"; cue: VideoCue };
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

**TypeScript equivalent**

```ts
// @observable — views auto-subscribe to these fields
class LiveState {
  // `private(set)` ⇒ public read, private write (readonly to the outside world)
  #content: Content = { kind: "empty" };
  get content() { return this.#content; }

  #program: ProgramSlide[] = [];
  get program() { return this.#program; }

  #index = 0;        get index() { return this.#index; }
  #started = false;  get started() { return this.#started; }
  #panic: Panic = { kind: "none" }; get panic() { return this.#panic; }

  transition: TransitionStyle = "fade";  // fully public — operator picks fade/cut
}
```

**Swift syntax:**
- `private(set) var x = …` — the getter is public, the setter is private. Outside code can read `live.index` but only `LiveState`'s methods can assign it. In TS you fake this with a private field `#x` plus a public `get x()`.
- `[ProgramSlide]` — array literal type, same as `ProgramSlide[]`.
- `= .empty` — leading-dot shorthand: the type is already known to be `Content`, so you can omit `Content` and write just the case name.

`liveSlideID` returns the id of the currently-live slide *only* when the show is started, not panicked, and the index is valid — otherwise `nil` (used to highlight the live cell in the grid). `nextProgramSlide` peeks at the slide a "next" press will reveal (for the inspector's preview); note that before the show starts it points at index `0`, after starting at `index + 1`.

```swift
var liveSlideID: PersistentIdentifier? {
    guard started, panic == .none, program.indices.contains(index) else { return nil }
    return program[index].id
}
```

**TypeScript equivalent**

```ts
get liveSlideID(): PersistentIdentifier | null {
  // guard: bail to null unless ALL conditions hold
  if (!(this.started && this.panic.kind === "none"
        && this.index >= 0 && this.index < this.program.length)) {
    return null;
  }
  return this.program[this.index].id;
}
```

**Swift syntax:**
- `guard A, B, C else { return nil }` — a comma-separated guard requires *all* conditions; if any fails it runs the `else` (which must exit). Equivalent to one big `if (!(A && B && C)) return null;`.
- `program.indices.contains(index)` — a bounds check (`0 <= index < count`), like `index >= 0 && index < program.length`.

**Program control** is the heart of the file:

- `arm(_:)` loads a program but sets `started = false` — so `recompute()` falls through to `.empty` and the output doesn't change.
- `goLive(id:)` jumps straight to a slide by id and sets `started = true`.
- `next()` has three branches: if panicked, a nav key *resumes* (clears panic); if not yet started, the first press starts at index 0; otherwise it advances, clamped to the last slide.
- `previous()` mirrors that (and is a no-op before the show starts).
- `setPanic(_:)` *toggles* — pressing Black again un-blacks.
- `clear()` wipes the whole program.

```swift
func arm(_ slides: [ProgramSlide]) {
    program = slides
    index = 0
    started = false
    panic = .none
    recompute()
}

func goLive(id: PersistentIdentifier) {
    guard let position = program.firstIndex(where: { $0.id == id }) else { return }
    index = position
    started = true
    panic = .none
    recompute()
}

func next() {
    guard hasProgram else { return }
    if panic != .none {
        panic = .none                       // a nav key resumes from a panic state
    } else if !started {
        started = true
        index = 0                           // first press starts the program
    } else {
        index = min(index + 1, program.count - 1)
    }
    recompute()
}

func setPanic(_ requested: Panic) {
    panic = (panic == requested) ? .none : requested   // toggle
    recompute()
}
```

**TypeScript equivalent**

```ts
// arm: load a program WITHOUT changing the screen (started = false)
arm(slides: ProgramSlide[]) {
  this.#program = slides;
  this.#index = 0;
  this.#started = false;
  this.#panic = { kind: "none" };
  this.recompute();
}

goLive(id: PersistentIdentifier) {
  const position = this.#program.findIndex(s => s.id === id);
  if (position === -1) return;             // guard let … else { return }
  this.#index = position;
  this.#started = true;
  this.#panic = { kind: "none" };
  this.recompute();
}

next() {
  if (this.#program.length === 0) return;
  if (this.#panic.kind !== "none") {
    this.#panic = { kind: "none" };        // a nav key resumes from panic
  } else if (!this.#started) {
    this.#started = true;
    this.#index = 0;                       // first press starts the program
  } else {
    this.#index = Math.min(this.#index + 1, this.#program.length - 1);
  }
  this.recompute();
}

setPanic(requested: Panic) {
  // toggle: pressing the same panic again clears it
  this.#panic = this.#panic.kind === requested.kind ? { kind: "none" } : requested;
  this.recompute();
}
```

**Swift syntax:**
- `func arm(_ slides: …)` — the `_` is an omitted external argument label, so callers write `arm(slides)` not `arm(slides: slides)`. (`func setPanic(_ requested:)` likewise → `setPanic(.black)`.)
- `guard let position = program.firstIndex(where: { … }) else { return }` — `guard let` unwraps an optional and binds it for the rest of the function, or exits. `firstIndex(where:)` returns `Int?` (nil if not found) → JS `findIndex` returning `-1`.
- `min(a, b)` / `program.count - 1` — clamp to the last valid index.
- `cond ? .none : requested` — ternary, identical to TS.

`previous()` mirrors `next()` (and is a no-op before the show starts). Every mutator ends by calling `recompute()`, which is the single place that derives `content` from the state:

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

**TypeScript equivalent**

```ts
private recompute() {
  switch (this.#panic.kind) {
    case "black":
      this.#content = { kind: "black" };
      break;
    case "logo":
      this.#content = { kind: "logo" };
      break;
    case "clear":
      // `case .clear where started && inBounds` = a guarded case
      if (this.#started && this.inBounds()) {
        this.#content = this.clearedContent(this.#program[this.#index]);
        break;
      }
      this.#content = { kind: "empty" };   // fell through the guard
      break;
    case "none":
      if (this.#started && this.inBounds()) {
        this.#content = this.liveContent(this.#program[this.#index]);
        break;
      }
      this.#content = { kind: "empty" };
      break;
    default:
      this.#content = { kind: "empty" };
  }
}
```

**Swift syntax:**
- `case .clear where started && …:` — a `where` clause adds a guard to a `case`. The case matches only when the boolean is also true; otherwise matching continues to the next case (eventually hitting `default`). TS has no direct form, so you re-check inside the case and fall through to the default value.
- `switch` in Swift has no fall-through by default and requires exhaustiveness (`default:` covers the rest). No `break` is needed — each case ends on its own.

`clearedContent(of:)` is a nice touch: "Clear" keeps the slide's background (color/video) but rebuilds the `RenderableSlide` with an empty `elements` array — so the text vanishes but the backdrop stays.

```swift
private func clearedContent(of slide: ProgramSlide) -> Content {
    switch slide.kind {
    case .slide(let renderable):
        .slide(RenderableSlide(backgroundColorHex: renderable.backgroundColorHex, elements: [],
                               backgroundVideo: renderable.backgroundVideo))
    case .video(let cue):
        .video(cue)
    }
}
```

**TypeScript equivalent**

```ts
private clearedContent(slide: ProgramSlide): Content {
  switch (slide.kind.kind) {
    case "slide": {
      const r = slide.kind.renderable;
      // keep background color + video, strip all text/elements
      return { kind: "slide", slide: {
        backgroundColorHex: r.backgroundColorHex,
        elements: [],
        backgroundVideo: r.backgroundVideo,
      }};
    }
    case "video":
      return { kind: "video", cue: slide.kind.cue }; // a clip has no text to clear
  }
}
```

**Swift syntax:**
- A `switch` used as an *expression*: each `case` body is a bare expression (no `return`) and the whole `switch` is the function's returned value (single-expression function bodies). In TS you write explicit `return` in each branch.

**Building programs** are the `static` factory functions that turn database models into value snapshots:

- `programSlides(for item: Item)` handles media items specially: it reads the filename, asks `MediaImport.kind(...)` whether it's video or image, and builds a `VideoCue` or an image-backed `RenderableSlide`. For normal items it maps each ordered slide through `RenderableSlide($0)`.
- `programSlides(for playlist:)` flattens every entry's item into one running list.
- `groupedProgram(for:)` produces the titled groups. The doc comment guarantees the grouped and flat versions share slide identities, so click-to-go-live and live-highlight stay aligned.

```swift
static func programSlides(for item: Item) -> [ProgramSlide] {
    if item.kind == .media {
        guard let filename = item.mediaFilename else { return [] }
        switch MediaImport.kind(forExtension: (filename as NSString).pathExtension) {
        case .video:
            let cue = VideoCue(url: MediaStorage.url(forFilename: filename),
                               loops: item.videoLoops,
                               muted: item.videoMuted,
                               endBehavior: item.videoEndBehavior)
            return [ProgramSlide(id: item.persistentModelID, kind: .video(cue), sectionLabel: item.title)]
        case .image:
            let renderable = RenderableSlide(backgroundColorHex: "#000000", elements: [],
                                             backgroundImageURL: MediaStorage.url(forFilename: filename))
            return [ProgramSlide(id: item.persistentModelID, kind: .slide(renderable), sectionLabel: item.title)]
        case nil:
            return []
        }
    }
    return item.orderedSlides.map {
        ProgramSlide(id: $0.persistentModelID,
                     kind: .slide(RenderableSlide($0)),
                     sectionLabel: $0.sectionLabel)
    }
}

static func programSlides(for playlist: Playlist) -> [ProgramSlide] {
    playlist.orderedEntries.compactMap(\.item).flatMap(programSlides(for:))
}
```

**TypeScript equivalent**

```ts
// static — a class-level factory; turns a DB model into VALUE snapshots
static programSlides(item: Item): ProgramSlide[] {
  if (item.kind === "media") {
    const filename = item.mediaFilename;
    if (filename == null) return [];        // guard let … else { return [] }
    switch (MediaImport.kind(extOf(filename))) {  // MediaKind | null
      case "video": {
        const cue: VideoCue = {
          url: MediaStorage.url(filename),
          loops: item.videoLoops,
          muted: item.videoMuted,
          endBehavior: item.videoEndBehavior,
        };
        return [{ id: item.persistentModelID, kind: { kind: "video", cue },
                  sectionLabel: item.title }];
      }
      case "image": {
        const renderable: RenderableSlide = {
          backgroundColorHex: "#000000", elements: [],
          backgroundImageURL: MediaStorage.url(filename),
        };
        return [{ id: item.persistentModelID,
                  kind: { kind: "slide", renderable }, sectionLabel: item.title }];
      }
      case null:
        return [];
    }
  }
  return item.orderedSlides.map(s => ({
    id: s.persistentModelID,
    kind: { kind: "slide", renderable: makeRenderable(s) }, // RenderableSlide($0)
    sectionLabel: s.sectionLabel,
  }));
}

static programSlides(playlist: Playlist): ProgramSlide[] {
  return playlist.orderedEntries
    .map(e => e.item)              // .compactMap(\.item) ⇒ map then drop nulls
    .filter((i): i is Item => i != null)
    .flatMap(i => LiveState.programSlides(i));  // .flatMap(programSlides(for:))
}
```

**Swift syntax:**
- `static func` — a type-level (class) method; called as `LiveState.programSlides(for: item)` → TS `static`.
- `case nil:` in the `switch` — `MediaImport.kind(...)` returns `MediaKind?`, and you can pattern-match `nil` as one of the cases (the unsupported-type branch).
- `(filename as NSString).pathExtension` — a bridge cast to the Objective-C `NSString` to reuse its `pathExtension` helper → `extOf(filename)`.
- `RenderableSlide($0)` — calls an initializer that takes a `Slide` model and builds a value snapshot; `$0` is the closure's first arg → `makeRenderable(s)`.
- `compactMap(\.item)` — `compactMap` maps then drops `nil`s; `\.item` is a *key-path* shorthand for the closure `{ $0.item }` → `.map(e => e.item).filter(x => x != null)`.
- `flatMap(programSlides(for:))` — passes the function itself as the transform (point-free); `programSlides(for:)` names the function by its argument label → `.flatMap(i => programSlides(i))`.

`groupedProgram(for:)` produces the titled groups (one per playlist entry). Finally, `TransitionStyle` is a tiny string-backed enum (`cut` / `fade`) with a display label, used by the output's animation:

```swift
enum TransitionStyle: String, CaseIterable, Identifiable {
    case cut, fade
    var id: String { rawValue }
    var label: String { self == .cut ? "Cut" : "Fade" }
}
```

**TypeScript equivalent**

```ts
// String-backed enum with helpers ⇒ a string union + lookup tables
type TransitionStyle = "cut" | "fade";
const TransitionStyle = {
  allCases: ["cut", "fade"] as TransitionStyle[],   // CaseIterable
  id: (t: TransitionStyle) => t,                     // Identifiable
  label: (t: TransitionStyle) => (t === "cut" ? "Cut" : "Fade"),
};
```

**Swift syntax:**
- `enum X: String` — a *raw-value* enum: each case has a backing `String` (`"cut"`, `"fade"`) via `rawValue`, good for storage/serialization → a string union plus the literal values.
- `CaseIterable` — auto-synthesizes `.allCases` listing every case (for building pickers).

## How it connects

`LiveState` is created once in `JerusalemApp` and injected via `.environment(...)`. The operator window calls `arm`, `next`, `previous`, `goLive`, `setPanic`, `clear` in response to keys/clicks. `OutputController` holds a reference to it and hands it to `OutputView`, which reads `live.content` and renders it through the shared `SlideView` / `SlideRenderer` (for slides) or `VideoPlayerView` (for clips). The factory functions consume `Item` / `Playlist` SwiftData models but emit only value snapshots.

## Gotchas / why it matters

- **Arm vs. go-live is the safety mechanism.** Loading the next song never touches the screen; only an explicit operator action does. This is "never fail on Sunday" by design.
- **Value snapshots, not models.** `content` holds `RenderableSlide` / `VideoCue` structs. Even if someone edits the original song in another window, the live screen can't change until the operator re-arms or navigates. Never push a `@Model` object into here.
- **`recompute()` is the only writer of `content`.** Keep it that way — every state change funnels through one resolver, so the output can never be left in an inconsistent state.
- **Panic toggles and nav-resumes-from-panic.** A flustered operator can hit Black, then press the arrow key and the show resumes exactly where it was — no lost place.
- **`@MainActor`** guarantees all of this runs on the UI thread, matching the renderer's main-thread requirement.
