# `VideoCue.swift`

> An immutable value type describing a video clip to play on the output (file URL + loop / mute / end behavior) — safe to live inside `LiveState`'s snapshot because it's a copied value, not a live model.

**Location:** `Sources/Jerusalem/Media/VideoCue.swift`
**Role:** value type

## What it does (plain English)

A `VideoCue` is the complete, self-contained recipe for playing one clip: where the file is, whether it loops, whether it's muted, and what to do when a non-looping clip ends. It carries no behavior — it's pure data the live path and player read.

It's deliberately a `struct` (a value type), which is the linchpin of the project's edit/live separation. Because a `VideoCue` is *copied* whenever it's passed around, the copy that's "live" on the audience screen is independent of anything still being edited in a database model. That's why `LiveState.content` can safely hold a `VideoCue` — there's no shared reference that an edit could mutate out from under the output.

Alongside it lives `VideoEndBehavior`, the small union of what should happen at a clip's end: hold the last frame, go to black, or advance to the next program item.

## Swift you'll meet in this file

- `struct VideoCue` — a value type, *copied* on assignment (unlike a `class`, which is shared by reference) → an immutable TS `interface` / `readonly` data object. This is what makes snapshots safe.
- `enum VideoEndBehavior: String` — a TS-style union whose cases are backed by raw string values → `type … = "hold" | "black" | "advance"` (good for storage/serialization).
- Protocol conformances:
  - `Equatable` / `Hashable` — value equality and usability as a dictionary/set key (e.g. caching by cue) → structural `===`-by-value + hashable for `Map`/`Set` keys.
  - `Codable` — JSON-style encode/decode for persistence → `JSON.stringify`/`parse`.
  - `CaseIterable` — `.allCases` lists every case (for building a picker).
  - `Identifiable` — has an `id` (here the raw string), so SwiftUI lists can track it.
  - `Sendable` — safe to pass across concurrency boundaries (threads/actors) → no TS analog (single-threaded).
- `var id: String { rawValue }` / `var label: String { ... }` — computed properties (getters), like JS getters.
- `switch self { case .hold: "..." }` — exhaustive match; each branch's expression is the returned value.
- `let` = `const`; `URL` = a file URL; `Bool` = boolean.

## Code walkthrough

`VideoEndBehavior` is the end-of-clip union, string-backed and UI-ready:

```swift
enum VideoEndBehavior: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case hold, black, advance
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hold:    "Hold last frame"
        case .black:   "Go to black"
        case .advance: "Advance to next"
        }
    }
}
```

**TypeScript equivalent**

```ts
// String raw enum ⇒ a string union, with the literals doubling as stable IDs
type VideoEndBehavior = "hold" | "black" | "advance";

const VideoEndBehavior = {
  allCases: ["hold", "black", "advance"] as VideoEndBehavior[],  // CaseIterable
  id: (b: VideoEndBehavior) => b,                                 // Identifiable
  label: (b: VideoEndBehavior): string => {
    switch (b) {                          // exhaustive switch (no default needed)
      case "hold":    return "Hold last frame";
      case "black":   return "Go to black";
      case "advance": return "Advance to next";
    }
  },
};
```

**Swift syntax:**
- `enum VideoEndBehavior: String, Codable, CaseIterable, …` — a *raw-value* enum (`: String`) plus a list of *protocol conformances*. The cases get a backing string (`"hold"` etc.) via `rawValue`, and each protocol synthesizes behavior: `Codable` (de/serialize), `CaseIterable` (`.allCases`), `Identifiable` (`id`), `Hashable`/`Sendable`. → a string union plus a few helper tables.
- `var id: String { rawValue }` — a computed getter returning the case's raw string → `get id() { return this }`.
- `var label: String { switch self { case .hold: "…" } }` — the `switch` is an *expression*: each `case` is a bare value (no `return`) and the whole switch is the property's value. Exhaustive, so no `default` is needed. → a `switch` with explicit `return`s.

The `String` raw type gives each case a stable string (`"hold"`, `"black"`, `"advance"`) for storage; `id` reuses it for SwiftUI; `label` provides the human-readable text shown in a picker. `CaseIterable` lets the UI list all three options. The behaviors map directly to runtime actions you can trace into `VideoPlayerView`: `.black` hides the player layer at end, `.advance` triggers `LiveState.next()`, `.hold` just leaves the last frame up.

`VideoCue` itself is four stored fields and nothing else:

```swift
struct VideoCue: Equatable, Hashable, Sendable {
    var url: URL
    var loops: Bool
    var muted: Bool
    var endBehavior: VideoEndBehavior
}
```

**TypeScript equivalent**

```ts
// struct ⇒ an immutable value object: copied on pass, compared by value.
// readonly fields signal "snapshot, don't mutate" (the edit/live firewall).
interface VideoCue {
  readonly url: URL;
  readonly loops: boolean;
  readonly muted: boolean;
  readonly endBehavior: VideoEndBehavior;
}
// Equatable/Hashable ⇒ value equality + usable as a Map/Set key
// (e.g. VideoPlayerView's `cue != currentCue` change-check, and prewarm caching)
```

**Swift syntax:**
- `struct VideoCue: Equatable, Hashable, Sendable` — a value type (copied on assignment/passing, not shared by reference like a `class`). The conformances give it value `==` (`Equatable`), hashability for `Set`/dictionary keys (`Hashable`), and cross-thread safety (`Sendable`). → an immutable interface; "copied on pass" is what makes it a safe live snapshot.
- `var url: URL` inside a `struct` — fields are `var` (settable) but because the *whole struct* is copied, mutating a copy can't affect the live one. The renderer/live path treat cues as immutable. → `readonly` to signal the intent.

Pure data. Its `Equatable`/`Hashable` conformance is load-bearing: `VideoPlayerView.apply(_:)` uses `cue != currentCue` to skip restarting an unchanged clip, and `VideoPrewarmer` keys its cache by URL derived from cues.

## How it connects

Built by `LiveState.programSlides(for:)` from a media `Item` (reading `videoLoops`, `videoMuted`, `videoEndBehavior` off the model into this immutable snapshot). Stored inside `LiveState`'s `ProgramSlide.Kind.video` and `Content.video`. Consumed by `VideoPlayerView` (which reads `url`/`loops`/`muted`/`endBehavior` to configure AVFoundation) and `VideoPrewarmer` (which pre-buffers by URL). `MediaAudit.isPresent(_ cue:)` checks its file exists.

## Gotchas / why it matters

- **It's a `struct` on purpose.** Value semantics (copy-on-pass) are exactly why a `VideoCue` can sit in the live snapshot without any edit leaking onto the audience screen. Never replace it with a `class`.
- **`Equatable`/`Hashable` are used for real** — change-detection in the player and caching in the prewarmer both depend on cue equality. Keep the conformances.
- **`endBehavior` is contractual** — `VideoPlayerView` and `OutputView` switch on it. Adding a case means handling it in both the player (`handleEnd`) and the output's auto-advance wiring.
- **String-backed enum** keeps the persisted value stable across app versions (matching the project's "enum stored as raw string" SwiftData convention).
